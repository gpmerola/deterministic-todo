package app.deterministic.todo.h96remote;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/**
 * One-shot mDNS lookup of Android TV remote services on the LAN. Runs only on request,
 * stops after a few seconds and never scans ports.
 */
public final class BoxDiscovery {
    public static final String SERVICE_TYPE = "_androidtvremote2._tcp.";
    static final long DURATION_MS = 4000;

    public static final class Found {
        public final String name;
        public final String host;

        Found(String name, String host) {
            this.name = name;
            this.host = host;
        }
    }

    public interface Callback {
        void onResult(List<Found> boxes);
    }

    private BoxDiscovery() {}

    @SuppressWarnings("deprecation") // resolveService is the API available down to minSdk 26.
    public static void run(Context context, Callback callback) {
        NsdManager nsd = (NsdManager) context.getApplicationContext().getSystemService(Context.NSD_SERVICE);
        Handler main = new Handler(Looper.getMainLooper());
        Deque<NsdServiceInfo> pending = new ArrayDeque<>();
        List<Found> found = new ArrayList<>();
        boolean[] finished = {false};
        boolean[] resolving = {false};

        NsdManager.DiscoveryListener[] listener = new NsdManager.DiscoveryListener[1];
        Runnable finish = () -> {
            if (finished[0]) return;
            finished[0] = true;
            try {
                nsd.stopServiceDiscovery(listener[0]);
            } catch (RuntimeException ignored) {
                // Already stopped.
            }
            callback.onResult(new ArrayList<>(found));
        };

        Runnable[] resolveNext = new Runnable[1];
        resolveNext[0] = () -> {
            if (finished[0] || resolving[0] || pending.isEmpty()) return;
            resolving[0] = true;
            nsd.resolveService(pending.poll(), new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo info, int errorCode) {
                    main.post(() -> { resolving[0] = false; resolveNext[0].run(); });
                }

                @Override public void onServiceResolved(NsdServiceInfo info) {
                    main.post(() -> {
                        resolving[0] = false;
                        if (info.getHost() != null)
                            found.add(new Found(info.getServiceName(), info.getHost().getHostAddress()));
                        resolveNext[0].run();
                    });
                }
            });
        };

        listener[0] = new NsdManager.DiscoveryListener() {
            @Override public void onStartDiscoveryFailed(String type, int code) { main.post(finish); }
            @Override public void onStopDiscoveryFailed(String type, int code) {}
            @Override public void onDiscoveryStarted(String type) {}
            @Override public void onDiscoveryStopped(String type) {}
            @Override public void onServiceLost(NsdServiceInfo info) {}
            @Override public void onServiceFound(NsdServiceInfo info) {
                main.post(() -> { pending.add(info); resolveNext[0].run(); });
            }
        };
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener[0]);
        main.postDelayed(finish, DURATION_MS);
    }
}
