package app.deterministic.todo.h96remote;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.interfaces.RSAPublicKey;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;

/**
 * Facade for the host app: the only class a UI bridge needs. Callbacks run on the main thread.
 * Nothing starts until the UI asks: no work at app start, no background service.
 * Typed text is passed straight to the socket and never logged or stored.
 */
public final class H96RemoteController {
    public static final int REMOTE_PORT = 6466;
    public static final int PAIRING_PORT = 6467;

    public interface Events {
        void onState(String state, String failure);

        void onVolume(int level, int max, boolean muted);

        /** Milliseconds to open the encrypted connection; high values mean a weak link. */
        void onLatency(long millis);
    }

    public interface Result<T> {
        void ok(T value);

        void error(String code);
    }

    private final Context context;
    private final Events events;
    private final BoxStore store;
    private final ClientIdentity identity = new KeyStoreIdentity();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService pairingExecutor = Executors.newSingleThreadExecutor();
    private ScheduledExecutorService sessionExecutor;
    private RemoteSession session;
    private boolean rediscovered;
    private android.net.wifi.WifiManager.WifiLock wifiLock;

    // WiZ light: independent of the TV session, own thread, created on first use.
    private final WizClient wiz = new WizClient();
    private ExecutorService lightExecutor;

    // Pairing state, confined to pairingExecutor.
    private PairingSession pairing;
    private PinningTrustManager pairingTrust;
    private String pairingHost;
    private String pairingName;

    public H96RemoteController(Context context, Events events) {
        this.context = context.getApplicationContext();
        this.events = events;
        this.store = new BoxStore(this.context);
    }

    public Map<String, Object> status() {
        BoxStore.Box box = store.load();
        Map<String, Object> value = new HashMap<>();
        value.put("paired", box != null);
        value.put("name", box == null ? "" : box.name);
        value.put("host", box == null ? "" : box.host);
        value.put("state", session == null ? RemoteSession.State.IDLE.name() : session.state().name());
        return value;
    }

    public void discover(Result<List<Map<String, Object>>> result) {
        BoxDiscovery.run(context, boxes -> {
            List<Map<String, Object>> list = new ArrayList<>();
            for (BoxDiscovery.Found box : boxes) {
                Map<String, Object> item = new HashMap<>();
                item.put("name", box.name);
                item.put("host", box.host);
                list.add(item);
            }
            result.ok(list);
        });
    }

    /** Makes the TV show a pairing code. */
    public void startPairing(String host, String name, Result<Void> result) {
        if (!LanAddress.isPrivate(host)) {
            result.error("invalid_host");
            return;
        }
        pairingExecutor.execute(() -> {
            closePairing();
            try {
                startPairingSession(host);
                pairingHost = host;
                pairingName = name == null || name.isEmpty() ? host : name;
                post(() -> result.ok(null));
            } catch (javax.net.ssl.SSLException | GeneralSecurityException e) {
                logFailure("pairing", e);
                closePairing();
                post(() -> result.error("tls_failed"));
            } catch (IOException e) {
                logFailure("pairing", e);
                closePairing();
                post(() -> result.error("unreachable"));
            }
        });
    }

    /** One retry for plain network errors: a sleeping box may miss the first attempt. */
    private void startPairingSession(String host) throws IOException, GeneralSecurityException {
        for (int attempt = 1; ; attempt++) {
            pairingTrust = new PinningTrustManager(null);
            TlsTransport transport = new TlsTransport(host, PAIRING_PORT,
                TlsContexts.factory(identity, pairingTrust));
            pairing = new PairingSession(transport, clientName());
            try {
                pairing.start();
                return;
            } catch (javax.net.ssl.SSLException e) {
                throw e;
            } catch (IOException e) {
                closePairing();
                if (attempt >= 2) throw e;
                logFailure("pairing attempt", e);
            }
        }
    }

    public void finishPairing(String code, Result<Void> result) {
        pairingExecutor.execute(() -> {
            if (pairing == null || pairingTrust == null || pairingTrust.seen() == null) {
                post(() -> result.error("no_pairing"));
                return;
            }
            try {
                X509Certificate server = pairingTrust.seen();
                byte[] secret = PairingSecret.compute(code, identity.publicKey(),
                    (RSAPublicKey) server.getPublicKey());
                if (secret == null) {
                    // Wrong code: keep the session open so the user can retype it.
                    post(() -> result.error("bad_code"));
                    return;
                }
                pairing.finish(secret);
                store.save(pairingHost, pairingName, PinningTrustManager.fingerprint(server));
                closePairing();
                post(() -> result.ok(null));
            } catch (PairingSession.BadSecretException e) {
                closePairing();
                post(() -> result.error("bad_code"));
            } catch (IOException | GeneralSecurityException | ClassCastException e) {
                logFailure("finish", e);
                closePairing();
                post(() -> result.error("pairing_failed"));
            }
        });
    }

    public void cancelPairing() {
        pairingExecutor.execute(this::closePairing);
    }

    public void connect() {
        BoxStore.Box box = store.load();
        if (box == null) {
            events.onState(RemoteSession.State.FAILED.name(), RemoteSession.Failure.NOT_PAIRED.name());
            return;
        }
        disconnect();
        rediscovered = false;
        acquireWifiLock();
        startSession(box);
    }

    public void disconnect() {
        releaseWifiLock();
        if (session != null) session.stop();
        session = null;
        if (sessionExecutor != null) sessionExecutor.shutdown();
        sessionExecutor = null;
    }

    public boolean send(String command) {
        RemoteCommand parsed = RemoteCommand.parse(command);
        return parsed != null && session != null && session.send(parsed);
    }

    public boolean hold(String command, boolean start) {
        RemoteCommand parsed = RemoteCommand.parse(command);
        return parsed != null && session != null && session.hold(parsed, start);
    }

    /** Opens an app shortcut; only the fixed links in {@link RemoteApp} can be sent. */
    public boolean launch(String app) {
        RemoteApp parsed = RemoteApp.parse(app);
        return parsed != null && session != null && session.launch(parsed.link);
    }

    public boolean sendText(String text) {
        return text != null && session != null && session.sendText(text);
    }

    // --- WiZ light -------------------------------------------------------------------

    /** State of the chosen bulb: {known, reachable, host, on, dimming, r, g, b, kelvin}. */
    public void lightState(Result<Map<String, Object>> result) {
        light(() -> {
            android.content.SharedPreferences prefs = lightPrefs();
            String host = prefs.getString("wiz_host", null);
            Map<String, Object> value = new HashMap<>();
            value.put("known", host != null);
            value.put("reachable", false);
            if (host == null) return value;
            WizProtocol.Pilot pilot = pilot(host);
            if (pilot == null) {
                // DHCP may have moved the bulb: find it again by its MAC address.
                String mac = prefs.getString("wiz_mac", "");
                for (WizClient.Found found : wiz.discover(1500).values()) {
                    if (!mac.isEmpty() && mac.equals(found.pilot.mac)) {
                        host = found.host;
                        prefs.edit().putString("wiz_host", host).apply();
                        pilot = found.pilot;
                        break;
                    }
                }
            }
            value.put("host", host);
            if (pilot != null) putPilot(value, pilot);
            return value;
        }, result);
    }

    public void lightDiscover(Result<List<Map<String, Object>>> result) {
        light(() -> {
            List<Map<String, Object>> list = new ArrayList<>();
            for (WizClient.Found found : wiz.discover(2000).values()) {
                Map<String, Object> item = new HashMap<>();
                item.put("host", found.host);
                item.put("mac", found.pilot.mac);
                list.add(item);
            }
            return list;
        }, result);
    }

    public void lightChoose(String host, String mac) {
        if (host == null || !LanAddress.isPrivate(host)) return;
        lightPrefs().edit().putString("wiz_host", host).putString("wiz_mac", mac == null ? "" : mac).apply();
    }

    static final String WIZ_PACKAGE = "com.wizconnected.wiz2";

    /** Opens the official WiZ app, which works through its cloud on mobile data. */
    public boolean openWizApp(android.app.Activity activity) {
        android.content.Intent intent =
            activity.getPackageManager().getLaunchIntentForPackage(WIZ_PACKAGE);
        if (intent == null) return false;
        activity.startActivity(intent);
        return true;
    }

    public void lightForget() {
        lightPrefs().edit().remove("wiz_host").remove("wiz_mac").apply();
    }

    /** kind is power, dimming, color or white; returns true when the bulb acknowledged. */
    public void lightCommand(String kind, Map<String, Object> args, Result<Boolean> result) {
        String json;
        switch (kind == null ? "" : kind) {
            case "power" -> json = WizProtocol.power(Boolean.TRUE.equals(args.get("on")));
            case "dimming" -> json = WizProtocol.dimming(intArg(args, "value", 100));
            case "color" -> json = WizProtocol.color(intArg(args, "r", 255), intArg(args, "g", 255),
                intArg(args, "b", 255));
            case "white" -> json = WizProtocol.white(intArg(args, "kelvin", 2700));
            default -> {
                result.error("invalid_command");
                return;
            }
        }
        light(() -> {
            String host = lightPrefs().getString("wiz_host", null);
            return host != null && WizProtocol.isSuccess(wiz.request(host, json));
        }, result);
    }

    private interface LightTask<T> {
        T run() throws IOException;
    }

    private <T> void light(LightTask<T> task, Result<T> result) {
        if (lightExecutor == null) lightExecutor = Executors.newSingleThreadExecutor();
        lightExecutor.execute(() -> {
            try {
                T value = task.run();
                post(() -> result.ok(value));
            } catch (IOException e) {
                post(() -> result.error("unreachable"));
            }
        });
    }

    private WizProtocol.Pilot pilot(String host) {
        try {
            return WizProtocol.parsePilot(wiz.request(host, WizProtocol.getPilot()));
        } catch (IOException e) {
            return null;
        }
    }

    private static void putPilot(Map<String, Object> value, WizProtocol.Pilot pilot) {
        value.put("reachable", true);
        value.put("on", pilot.on);
        value.put("dimming", pilot.dimming);
        value.put("r", pilot.r);
        value.put("g", pilot.g);
        value.put("b", pilot.b);
        value.put("kelvin", pilot.kelvin);
    }

    private static int intArg(Map<String, Object> args, String key, int fallback) {
        Object value = args.get(key);
        return value instanceof Number number ? number.intValue() : fallback;
    }

    private android.content.SharedPreferences lightPrefs() {
        return context.getSharedPreferences("h96_remote", Context.MODE_PRIVATE);
    }

    /** Forgets the box and deletes this phone's key, so the pairing cannot be reused. */
    public void forget() {
        disconnect();
        cancelPairing();
        store.clear();
        KeyStoreIdentity.delete();
    }

    private void startSession(BoxStore.Box box) {
        sessionExecutor = Executors.newSingleThreadScheduledExecutor();
        PinningTrustManager trust = new PinningTrustManager(box.pin);
        RemoteSession[] owner = new RemoteSession[1];
        RemoteSession next = new RemoteSession((host, port) -> {
            try {
                return new TlsTransport(host, port, TlsContexts.factory(identity, trust));
            } catch (GeneralSecurityException e) {
                throw new IllegalStateException(e);
            }
        }, box.host, REMOTE_PORT, sessionExecutor, new RemoteSession.Listener() {
            @Override public void onState(RemoteSession.State state, RemoteSession.Failure failure) {
                post(() -> onSessionState(owner[0], state, failure));
            }

            @Override public void onVolume(RemoteProtocol.Volume volume) {
                post(() -> events.onVolume(volume.level, volume.max, volume.muted));
            }

            @Override public void onHandshake(long millis) {
                post(() -> events.onLatency(millis));
            }
        });
        owner[0] = next;
        session = next;
        next.start();
    }

    private void onSessionState(RemoteSession owner, RemoteSession.State state, RemoteSession.Failure failure) {
        if (owner != session) return;
        if (state == RemoteSession.State.FAILED && failure == RemoteSession.Failure.UNREACHABLE && !rediscovered) {
            // The box may have a new DHCP address: look it up once; the pin still proves identity.
            rediscovered = true;
            events.onState(RemoteSession.State.RECONNECTING.name(), failure.name());
            BoxDiscovery.run(context, boxes -> {
                BoxStore.Box box = store.load();
                if (box == null || owner != session) return;
                for (BoxDiscovery.Found found : boxes) {
                    if (!found.host.equals(box.host)) {
                        store.updateHost(found.host);
                        disconnectKeepingFlag();
                        startSession(store.load());
                        return;
                    }
                }
                events.onState(state.name(), failure.name());
            });
            return;
        }
        events.onState(state.name(), failure.name());
    }

    private void disconnectKeepingFlag() {
        boolean flag = rediscovered;
        disconnect();
        rediscovered = flag;
        acquireWifiLock();
    }

    /**
     * While the remote screen is open, keep the phone's Wi-Fi out of power saving so key
     * presses leave at once. Android honours the low-latency lock only in the foreground with
     * the screen on, and it is released as soon as the screen closes or the app is paused.
     */
    @SuppressWarnings("deprecation") // WIFI_MODE_FULL_HIGH_PERF is the fallback below API 29.
    private void acquireWifiLock() {
        if (wifiLock != null) return;
        android.net.wifi.WifiManager wifi =
            (android.net.wifi.WifiManager) context.getSystemService(Context.WIFI_SERVICE);
        if (wifi == null) return;
        int mode = Build.VERSION.SDK_INT >= 29
            ? android.net.wifi.WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            : android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF;
        wifiLock = wifi.createWifiLock(mode, "h96remote");
        wifiLock.setReferenceCounted(false);
        wifiLock.acquire();
    }

    private void releaseWifiLock() {
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        wifiLock = null;
    }

    private void closePairing() {
        if (pairing != null) pairing.close();
        pairing = null;
        pairingTrust = null;
        pairingHost = null;
        pairingName = null;
    }

    /** Exception class and its cause class only: never hosts, codes or typed text. */
    static void logFailure(String step, Exception e) {
        Throwable cause = e.getCause();
        android.util.Log.w("H96Remote", step + " failed: " + e.getClass().getSimpleName()
            + (cause == null ? "" : " <- " + cause.getClass().getSimpleName()));
    }

    private void post(Runnable runnable) {
        main.post(runnable);
    }

    private static String clientName() {
        String model = Build.MODEL == null ? "" : Build.MODEL.trim();
        return model.isEmpty() ? "Todo remote" : "Todo · " + model;
    }
}
