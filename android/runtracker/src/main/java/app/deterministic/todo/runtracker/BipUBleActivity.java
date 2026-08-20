package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothStatusCodes;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.IntSummaryStatistics;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bounded Bip U diagnostics: battery or authenticated live heart-rate sampling. */
public final class BipUBleActivity extends ComponentActivity {
    private static final UUID BATTERY_SERVICE = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb");
    private static final UUID BATTERY_LEVEL = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb");
    private static final UUID HUAMI_AUTH_SERVICE = UUID.fromString("0000fee1-0000-1000-8000-00805f9b34fb");
    private static final UUID HUAMI_AUTH = UUID.fromString("00000009-0000-3512-2118-0009af100700");
    private static final UUID HEART_RATE_SERVICE = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb");
    private static final UUID HEART_RATE_MEASUREMENT = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb");
    private static final UUID HEART_RATE_CONTROL = UUID.fromString("00002a39-0000-1000-8000-00805f9b34fb");
    private static final UUID CLIENT_CONFIGURATION = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final byte[] STOP_MANUAL_HEART_RATE = new byte[] {0x15, 0x02, 0x00};
    private static final byte[] START_CONTINUOUS_HEART_RATE = new byte[] {0x15, 0x01, 0x01};
    private static final byte[] STOP_CONTINUOUS_HEART_RATE = new byte[] {0x15, 0x01, 0x00};
    private static final long HEART_RATE_WINDOW_MILLIS = 60_000;
    private static final long AUTH_TIMEOUT_MILLIS = 20_000;
    private enum Mode { BATTERY, HEART_RATE }
    private enum Stage { IDLE, AUTH_NOTIFY, AUTH_CHALLENGE, AUTH_ENCRYPTED, HR_NOTIFY,
        HR_STOP_MANUAL, HR_START, HR_LISTENING, HR_STOP }
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;
    private EditText keyInput;
    private Button probe;
    private Button heartRateProbe;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private final AtomicBoolean reportWritten = new AtomicBoolean();
    private long attemptStartedAtMillis;
    private String connectionSource = "none";
    private Mode mode = Mode.BATTERY;
    private Stage stage = Stage.IDLE;
    private BluetoothGattCharacteristic authCharacteristic;
    private BluetoothGattCharacteristic heartRateMeasurement;
    private BluetoothGattCharacteristic heartRateControl;
    private byte[] authKey;
    private final List<Integer> heartRateSamples = new ArrayList<>();
    private Integer lastGattStatus;
    private Integer lastWriteType;
    private Integer authCharacteristicProperties;
    private String failedStage;

    static void open(Activity activity) { activity.startActivity(new Intent(activity, BipUBleActivity.class)); }

    private final ActivityResultLauncher<String[]> permissionRequest = registerForActivityResult(
        new ActivityResultContracts.RequestMultiplePermissions(), result -> {
            if (result.values().stream().allMatch(Boolean.TRUE::equals)) connectBondedOrScan();
            else failAttempt("Permessi Bluetooth non concessi", "permission_denied", null);
        }
    );

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("Amazfit Bip U");
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(dp(24), dp(24), dp(24), dp(24));
        status = new TextView(this); status.setTextSize(20); status.setTypeface(null, Typeface.BOLD); status.setText("Pronto per collegare il Bip U"); status.setPadding(0, 0, 0, dp(12)); root.addView(status);
        keyInput = new EditText(this); keyInput.setHint("Chiave Huami · 32 caratteri esadecimali"); keyInput.setSingleLine(true); keyInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD); root.addView(keyInput);
        SecureAuthKeyStore keys = new SecureAuthKeyStore(this);
        if (keys.hasKey()) keyInput.setHint("Chiave Huami protetta già presente");
        Button save = new Button(this); save.setText("Proteggi chiave sul dispositivo"); save.setOnClickListener(v -> {
            try { keys.saveHex(keyInput.getText().toString()); keyInput.setText("");
                if (heartRateProbe != null) heartRateProbe.setEnabled(true);
                setStatus("Chiave salvata tramite Android Keystore; mai inserita nei log"); }
            catch (Exception error) { Toast.makeText(this, error.getMessage(), Toast.LENGTH_LONG).show(); }
        }); root.addView(save);
        probe = new Button(this); probe.setText("Collega Bip U e leggi batteria"); probe.setOnClickListener(v -> begin(Mode.BATTERY)); root.addView(probe);
        heartRateProbe = new Button(this); heartRateProbe.setText("Autentica e leggi battito · 60 s");
        heartRateProbe.setEnabled(keys.hasKey());
        heartRateProbe.setOnClickListener(v -> begin(Mode.HEART_RATE)); root.addView(heartRateProbe);
        TextView note = new TextView(this); note.setText("La prova cardiaca usa autenticazione e comandi temporanei, poi arresta la misura e si disconnette. Non modifica firmware o impostazioni persistenti. Chiave, MAC e pacchetti grezzi non entrano nei report."); note.setGravity(Gravity.CENTER); note.setPadding(0, dp(24), 0, 0); root.addView(note);
        setContentView(root);
    }

    private void begin(Mode requestedMode) {
        mode = requestedMode;
        stage = Stage.IDLE;
        heartRateSamples.clear();
        lastGattStatus = null;
        lastWriteType = null;
        authCharacteristicProperties = null;
        failedStage = null;
        authCharacteristic = null;
        heartRateMeasurement = null;
        heartRateControl = null;
        authKey = null;
        if (mode == Mode.HEART_RATE) {
            try {
                authKey = new SecureAuthKeyStore(this).read();
                if (authKey == null || authKey.length != 16) {
                    setStatus("Salva prima una chiave Huami valida");
                    return;
                }
            } catch (Exception error) {
                setStatus("Chiave Huami non leggibile; salvala nuovamente");
                return;
            }
        }
        ensurePermissions();
    }

    private void ensurePermissions() {
        attemptStartedAtMillis = System.currentTimeMillis();
        connectionSource = "none";
        reportWritten.set(false);
        ArrayList<String> missing = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 31) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.BLUETOOTH_SCAN);
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.BLUETOOTH_CONNECT);
        } else if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (missing.isEmpty()) connectBondedOrScan(); else permissionRequest.launch(missing.toArray(new String[0]));
    }

    private void connectBondedOrScan() {
        BluetoothManager manager = getSystemService(BluetoothManager.class);
        BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
        if (adapter == null || !adapter.isEnabled()) { failAttempt("Attiva il Bluetooth e riprova", "bluetooth_disabled", null); return; }
        try {
            for (BluetoothDevice device : adapter.getBondedDevices()) {
                if (BipUDeviceSelector.matchesName(device.getName())) {
                    connectionSource = "bonded";
                    setBusyStatus("Bip U già associato · connessione…");
                    connect(device);
                    return;
                }
            }
        } catch (SecurityException error) {
            failAttempt("Accesso ai dispositivi associati non autorizzato", "bonded_access_denied", null);
            return;
        }
        scan(adapter);
    }

    private void scan(BluetoothAdapter adapter) {
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { failAttempt("Scanner BLE non disponibile", "scanner_unavailable", null); return; }
        connectionSource = "scan";
        setBusyStatus("Ricerca Bip U per 12 secondi…");
        try { scanner.startScan(scanCallback); handler.postDelayed(() -> stopScan("Bip U non trovato"), 12_000); }
        catch (SecurityException error) { failAttempt("Permesso Bluetooth mancante", "scan_permission_denied", null); }
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            String name;
            try { name = device.getName(); } catch (SecurityException error) { return; }
            if (!BipUDeviceSelector.matchesName(name)) return;
            stopScan(null); setBusyStatus("Bip U trovato · connessione…"); connect(device);
        }
        @Override public void onScanFailed(int errorCode) {
            stopScan(null);
            failAttempt("Ricerca BLE non riuscita (" + errorCode + ")", "scan_failed", errorCode);
        }
    };

    private void connect(BluetoothDevice device) {
        runOnUiThread(() -> probe.setEnabled(false));
        try {
            BluetoothGatt previous = gatt;
            gatt = null;
            if (previous != null) previous.close();
            gatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            if (gatt == null) failAttempt("Connessione BLE non avviata", "connect_not_started", null);
        } catch (SecurityException error) {
            failAttempt("Connessione BLE non autorizzata", "connect_permission_denied", null);
        }
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(@NonNull BluetoothGatt connection, int statusCode, int newState) {
            if (connection != gatt) return;
            lastGattStatus = statusCode;
            if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                setBusyStatus("Connesso · lettura servizi…");
                try {
                    if (!connection.discoverServices())
                        failAttempt("Lettura servizi non avviata", "service_discovery_not_started", statusCode);
                } catch (SecurityException error) {
                    failAttempt("Accesso ai servizi non autorizzato", "service_discovery_denied", statusCode);
                }
            } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED) {
                if (mode == Mode.HEART_RATE) {
                    finishHeartRateAttempt(statusCode == BluetoothGatt.GATT_SUCCESS
                        ? "Bip U disconnesso prima della misura"
                        : "Connessione non riuscita (" + statusCode + ")",
                        statusCode == BluetoothGatt.GATT_SUCCESS ? "disconnected" : "connect_failed");
                } else {
                    finishAttempt(statusCode == BluetoothGatt.GATT_SUCCESS ? "Disconnesso" : "Connessione non riuscita (" + statusCode + ")",
                        statusCode == BluetoothGatt.GATT_SUCCESS ? "disconnected" : "connect_failed", null, statusCode);
                }
            }
        }
        @Override public void onServicesDiscovered(@NonNull BluetoothGatt connection, int statusCode) {
            if (connection != gatt) return;
            if (statusCode != BluetoothGatt.GATT_SUCCESS) {
                failAttempt("Connessione riuscita; lettura servizi non riuscita (" + statusCode + ")",
                    "service_discovery_failed", statusCode);
                return;
            }
            if (mode == Mode.HEART_RATE) {
                startHeartRateAuthentication(connection, statusCode);
                return;
            }
            BluetoothGattService service = connection.getService(BATTERY_SERVICE);
            BluetoothGattCharacteristic level = service == null ? null : service.getCharacteristic(BATTERY_LEVEL);
            if (level == null) { finishAttempt("Connesso; batteria standard non esposta prima dell’autenticazione", "battery_service_unavailable", null, statusCode); return; }
            try {
                if (!connection.readCharacteristic(level))
                    finishAttempt("Lettura batteria non avviata", "battery_read_not_started", null, statusCode);
            } catch (SecurityException error) {
                finishAttempt("Lettura batteria non autorizzata", "battery_read_denied", null, null);
            }
        }
        @Override public void onDescriptorWrite(@NonNull BluetoothGatt connection,
                                                @NonNull BluetoothGattDescriptor descriptor,
                                                int statusCode) {
            if (connection != gatt || mode != Mode.HEART_RATE) return;
            lastGattStatus = statusCode;
            if (statusCode != BluetoothGatt.GATT_SUCCESS) {
                finishHeartRateAttempt("Abilitazione notifiche BLE non riuscita", "notification_setup_failed");
                return;
            }
            if (stage == Stage.AUTH_NOTIFY) {
                stage = Stage.AUTH_CHALLENGE;
                setBusyStatus("Notifiche autenticazione attive · richiesta challenge…");
                if (!writeCharacteristic(connection, authCharacteristic,
                    HuamiAuthProtocol.requestChallenge()))
                    finishHeartRateAttempt("Challenge Huami non avviata", "auth_challenge_write_failed");
            } else if (stage == Stage.HR_NOTIFY) {
                stage = Stage.HR_STOP_MANUAL;
                setBusyStatus("Autenticato · avvio sensore cardiaco…");
                if (!writeCharacteristic(connection, heartRateControl, STOP_MANUAL_HEART_RATE))
                    finishHeartRateAttempt("Comando cardiaco non avviato", "heart_rate_control_failed");
            }
        }
        @Override public void onCharacteristicWrite(@NonNull BluetoothGatt connection,
                                                    @NonNull BluetoothGattCharacteristic characteristic,
                                                    int statusCode) {
            if (connection != gatt || mode != Mode.HEART_RATE) return;
            lastGattStatus = statusCode;
            if (statusCode != BluetoothGatt.GATT_SUCCESS) {
                failedStage = stage.name().toLowerCase(java.util.Locale.ROOT);
                String outcome = stage == Stage.AUTH_CHALLENGE
                    ? "auth_challenge_write_rejected"
                    : stage == Stage.AUTH_ENCRYPTED
                        ? "auth_response_write_rejected"
                        : "transient_write_failed";
                finishHeartRateAttempt("Scrittura BLE temporanea non riuscita", outcome);
                return;
            }
            if (stage == Stage.AUTH_CHALLENGE) {
                setBusyStatus("Challenge inviata · attendo risposta…");
            } else if (stage == Stage.AUTH_ENCRYPTED) {
                setBusyStatus("Risposta cifrata inviata · verifica…");
            } else if (stage == Stage.HR_STOP_MANUAL) {
                stage = Stage.HR_START;
                if (!writeCharacteristic(connection, heartRateControl, START_CONTINUOUS_HEART_RATE))
                    finishHeartRateAttempt("Avvio cardiaco non riuscito", "heart_rate_start_failed");
            } else if (stage == Stage.HR_START) {
                stage = Stage.HR_LISTENING;
                setBusyStatus("Sensore attivo · attendo il primo battito (massimo 60 s)…");
                handler.postDelayed(() -> stopHeartRateAndFinish(), HEART_RATE_WINDOW_MILLIS);
            } else if (stage == Stage.HR_STOP) {
                completeHeartRateAttempt();
            }
        }
        @Override public void onCharacteristicChanged(@NonNull BluetoothGatt connection,
                                                       @NonNull BluetoothGattCharacteristic characteristic,
                                                       byte[] value) {
            if (connection != gatt || mode != Mode.HEART_RATE) return;
            if (HUAMI_AUTH.equals(characteristic.getUuid())) {
                handleAuthenticationNotification(connection, value);
            } else if (HEART_RATE_MEASUREMENT.equals(characteristic.getUuid())) {
                Integer bpm = HeartRateMeasurementParser.parse(value);
                if (bpm != null) {
                    heartRateSamples.add(bpm);
                    setBusyStatus("Battito " + bpm + " bpm · campioni " + heartRateSamples.size()
                        + " · arresto automatico entro 60 s");
                }
            }
        }
        @SuppressWarnings("deprecation") @Override public void onCharacteristicChanged(
            @NonNull BluetoothGatt connection, @NonNull BluetoothGattCharacteristic characteristic) {
            onCharacteristicChanged(connection, characteristic, characteristic.getValue());
        }
        @Override public void onCharacteristicRead(@NonNull BluetoothGatt connection, @NonNull BluetoothGattCharacteristic characteristic, byte[] value, int statusCode) {
            if (connection != gatt) return;
            if (BATTERY_LEVEL.equals(characteristic.getUuid()) && statusCode == BluetoothGatt.GATT_SUCCESS && value.length > 0) {
                int percent = value[0] & 0xff;
                finishAttempt("Bip U connesso · batteria " + percent + "%", "battery_read_success", percent, statusCode);
            } else finishAttempt("Connesso; lettura batteria non riuscita", "battery_read_failed", null, statusCode);
        }
        @SuppressWarnings("deprecation") @Override public void onCharacteristicRead(
            @NonNull BluetoothGatt connection,
            @NonNull BluetoothGattCharacteristic characteristic,
            int statusCode
        ) {
            onCharacteristicRead(connection, characteristic, characteristic.getValue(), statusCode);
        }
    };

    private void startHeartRateAuthentication(BluetoothGatt connection, int statusCode) {
        BluetoothGattService authService = connection.getService(HUAMI_AUTH_SERVICE);
        BluetoothGattService heartService = connection.getService(HEART_RATE_SERVICE);
        authCharacteristic = authService == null ? null : authService.getCharacteristic(HUAMI_AUTH);
        heartRateMeasurement = heartService == null ? null
            : heartService.getCharacteristic(HEART_RATE_MEASUREMENT);
        heartRateControl = heartService == null ? null
            : heartService.getCharacteristic(HEART_RATE_CONTROL);
        if (authCharacteristic == null) {
            finishHeartRateAttempt("Servizio autenticazione Huami non disponibile",
                "auth_service_unavailable");
            return;
        }
        authCharacteristicProperties = authCharacteristic.getProperties();
        if (heartRateMeasurement == null || heartRateControl == null) {
            finishHeartRateAttempt("Servizio cardiaco Bip U non disponibile",
                "heart_rate_service_unavailable");
            return;
        }
        stage = Stage.AUTH_NOTIFY;
        setBusyStatus("Servizi trovati · abilito autenticazione…");
        handler.postDelayed(() -> {
            if (!reportWritten.get() && stage != Stage.HR_NOTIFY
                && stage != Stage.HR_STOP_MANUAL && stage != Stage.HR_START
                && stage != Stage.HR_LISTENING && stage != Stage.HR_STOP)
                finishHeartRateAttempt("Autenticazione Huami scaduta", "authentication_timeout");
        }, AUTH_TIMEOUT_MILLIS);
        if (!enableNotifications(connection, authCharacteristic))
            finishHeartRateAttempt("Notifiche autenticazione non disponibili",
                "auth_notifications_unavailable");
    }

    private void handleAuthenticationNotification(BluetoothGatt connection, byte[] value) {
        try {
            HuamiAuthProtocol.Result result = HuamiAuthProtocol.handle(value, authKey);
            if (result.kind() == HuamiAuthProtocol.Kind.CHALLENGE) {
                stage = Stage.AUTH_ENCRYPTED;
                if (!writeCharacteristic(connection, authCharacteristic, result.command()))
                    finishHeartRateAttempt("Risposta cifrata non inviata", "auth_response_write_failed");
            } else if (result.kind() == HuamiAuthProtocol.Kind.AUTHENTICATED) {
                handler.removeCallbacksAndMessages(null);
                authKey = null;
                stage = Stage.HR_NOTIFY;
                setBusyStatus("Autenticazione riuscita · abilito battito…");
                if (!enableNotifications(connection, heartRateMeasurement))
                    finishHeartRateAttempt("Notifiche cardiache non disponibili",
                        "heart_rate_notifications_unavailable");
            } else if (result.kind() == HuamiAuthProtocol.Kind.FAILED) {
                finishHeartRateAttempt("Autenticazione Huami rifiutata; verifica la chiave",
                    "authentication_failed");
            }
        } catch (Exception error) {
            finishHeartRateAttempt("Errore crittografico durante l’autenticazione",
                "authentication_crypto_failed");
        }
    }

    private boolean enableNotifications(BluetoothGatt connection,
                                        BluetoothGattCharacteristic characteristic) {
        try {
            if (!connection.setCharacteristicNotification(characteristic, true)) return false;
            BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION);
            if (descriptor == null) return false;
            if (Build.VERSION.SDK_INT >= 33)
                return connection.writeDescriptor(descriptor,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS;
            descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            return connection.writeDescriptor(descriptor);
        } catch (SecurityException error) {
            return false;
        }
    }

    private boolean writeCharacteristic(BluetoothGatt connection,
                                        BluetoothGattCharacteristic characteristic,
                                        byte[] value) {
        if (characteristic == null || value == null) return false;
        try {
            int writeType = GattWritePolicy.select(characteristic.getProperties(),
                characteristic.getWriteType(), characteristic == authCharacteristic);
            lastWriteType = writeType;
            if (Build.VERSION.SDK_INT >= 33)
                return connection.writeCharacteristic(characteristic, value,
                    writeType) == BluetoothStatusCodes.SUCCESS;
            characteristic.setWriteType(writeType);
            characteristic.setValue(value);
            return connection.writeCharacteristic(characteristic);
        } catch (SecurityException error) {
            return false;
        }
    }

    private void stopHeartRateAndFinish() {
        if (reportWritten.get() || stage == Stage.HR_STOP) return;
        handler.removeCallbacksAndMessages(null);
        if (gatt != null && heartRateControl != null) {
            stage = Stage.HR_STOP;
            setBusyStatus("Arresto sensore cardiaco…");
            if (writeCharacteristic(gatt, heartRateControl, STOP_CONTINUOUS_HEART_RATE)) {
                handler.postDelayed(this::completeHeartRateAttempt, 2_000);
                return;
            }
        }
        completeHeartRateAttempt();
    }

    private void finishHeartRateAttempt(String text, String outcome) {
        handler.removeCallbacksAndMessages(null);
        if (stage == Stage.HR_LISTENING || stage == Stage.HR_START || stage == Stage.HR_STOP) {
            if (gatt != null && heartRateControl != null) {
                stage = Stage.HR_STOP;
                writeCharacteristic(gatt, heartRateControl, STOP_CONTINUOUS_HEART_RATE);
            }
        }
        exportHeartRateResult(text, outcome);
    }

    private void completeHeartRateAttempt() {
        String outcome = heartRateSamples.isEmpty() ? "heart_rate_no_samples" : "heart_rate_read_success";
        String text = heartRateSamples.isEmpty()
            ? "Autenticato, ma nessun campione cardiaco ricevuto"
            : "Battito letto · " + heartRateSamples.size() + " campioni";
        exportHeartRateResult(text, outcome);
    }

    private void exportHeartRateResult(String text, String outcome) {
        if (!reportWritten.compareAndSet(false, true)) return;
        setStatus(text);
        IntSummaryStatistics summary = heartRateSamples.stream().mapToInt(Integer::intValue)
            .summaryStatistics();
        Integer minimum = summary.getCount() == 0 ? null : summary.getMin();
        Integer maximum = summary.getCount() == 0 ? null : summary.getMax();
        Double mean = summary.getCount() == 0 ? null : summary.getAverage();
        long startedAt = attemptStartedAtMillis > 0 ? attemptStartedAtMillis : System.currentTimeMillis();
        closeGatt();
        DriveTestExportManager.exportBipUHeartRateProbe(this, startedAt, connectionSource,
            outcome, heartRateSamples.size(), minimum, maximum, mean, lastGattStatus,
            failedStage, authCharacteristicProperties, lastWriteType,
            result -> runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || attemptStartedAtMillis != startedAt) return;
                status.setText(text + (result.success() ? "\nReport salvato su Drive"
                    : result.configured() ? "\nReport Drive non riuscito"
                    : "\nCartella Drive non collegata"));
            }));
    }

    private void closeGatt() {
        BluetoothGatt connection = gatt;
        gatt = null;
        authKey = null;
        try { if (connection != null) connection.close(); } catch (RuntimeException ignored) {}
    }

    private void stopScan(String fallback) {
        handler.removeCallbacksAndMessages(null);
        try { if (scanner != null) scanner.stopScan(scanCallback); } catch (SecurityException ignored) {}
        if (fallback != null && status.getText().toString().startsWith("Ricerca"))
            failAttempt(fallback, "not_found", null);
    }
    private void finishAttempt(String text, String outcome, Integer batteryPercent, Integer gattStatus) {
        setStatus(text);
        if (!reportWritten.compareAndSet(false, true)) return;
        closeGatt();
        long startedAt = attemptStartedAtMillis > 0 ? attemptStartedAtMillis : System.currentTimeMillis();
        DriveTestExportManager.exportBipUProbe(this, startedAt, connectionSource,
            outcome, batteryPercent, gattStatus, result -> runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || attemptStartedAtMillis != startedAt) return;
                status.setText(text + (result.success()
                    ? "\nReport salvato su Drive"
                    : result.configured() ? "\nReport Drive non riuscito" : "\nCartella Drive non collegata"));
            }));
    }
    private void failAttempt(String text, String outcome, Integer gattStatus) {
        if (mode == Mode.HEART_RATE) {
            lastGattStatus = gattStatus;
            finishHeartRateAttempt(text, outcome);
        } else finishAttempt(text, outcome, null, gattStatus);
    }
    private void setBusyStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(false); heartRateProbe.setEnabled(false); }); }
    private void setStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(true); heartRateProbe.setEnabled(new SecureAuthKeyStore(this).hasKey()); }); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override protected void onDestroy() { stopScan(null); closeGatt(); super.onDestroy(); }
}
