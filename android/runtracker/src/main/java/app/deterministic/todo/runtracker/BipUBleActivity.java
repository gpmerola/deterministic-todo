package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
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
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/** Minimal BLE probe: reuses a bonded device or scans, then reads battery data only. */
public final class BipUBleActivity extends ComponentActivity {
    private static final UUID BATTERY_SERVICE = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb");
    private static final UUID BATTERY_LEVEL = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb");
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;
    private EditText keyInput;
    private Button probe;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private final AtomicBoolean reportWritten = new AtomicBoolean();
    private long attemptStartedAtMillis;
    private String connectionSource = "none";

    static void open(Activity activity) { activity.startActivity(new Intent(activity, BipUBleActivity.class)); }

    private final ActivityResultLauncher<String[]> permissionRequest = registerForActivityResult(
        new ActivityResultContracts.RequestMultiplePermissions(), result -> {
            if (result.values().stream().allMatch(Boolean.TRUE::equals)) connectBondedOrScan();
            else finishAttempt("Permessi Bluetooth non concessi", "permission_denied", null, null);
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
            try { keys.saveHex(keyInput.getText().toString()); keyInput.setText(""); setStatus("Chiave salvata tramite Android Keystore; mai inserita nei log"); }
            catch (Exception error) { Toast.makeText(this, error.getMessage(), Toast.LENGTH_LONG).show(); }
        }); root.addView(save);
        probe = new Button(this); probe.setText("Collega Bip U e leggi batteria"); probe.setOnClickListener(v -> ensurePermissions()); root.addView(probe);
        TextView note = new TextView(this); note.setText("Questa prova non modifica impostazioni o firmware. L’autenticazione Huami e il download delle attività resteranno disattivati finché il protocollo indipendente non sarà validato sul tuo orologio."); note.setGravity(Gravity.CENTER); note.setPadding(0, dp(24), 0, 0); root.addView(note);
        setContentView(root);
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
        if (adapter == null || !adapter.isEnabled()) { finishAttempt("Attiva il Bluetooth e riprova", "bluetooth_disabled", null, null); return; }
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
            finishAttempt("Accesso ai dispositivi associati non autorizzato", "bonded_access_denied", null, null);
            return;
        }
        scan(adapter);
    }

    private void scan(BluetoothAdapter adapter) {
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { finishAttempt("Scanner BLE non disponibile", "scanner_unavailable", null, null); return; }
        connectionSource = "scan";
        setBusyStatus("Ricerca Bip U per 12 secondi…");
        try { scanner.startScan(scanCallback); handler.postDelayed(() -> stopScan("Bip U non trovato"), 12_000); }
        catch (SecurityException error) { finishAttempt("Permesso Bluetooth mancante", "scan_permission_denied", null, null); }
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
            finishAttempt("Ricerca BLE non riuscita (" + errorCode + ")", "scan_failed", null, errorCode);
        }
    };

    private void connect(BluetoothDevice device) {
        runOnUiThread(() -> probe.setEnabled(false));
        try {
            BluetoothGatt previous = gatt;
            gatt = null;
            if (previous != null) previous.close();
            gatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            if (gatt == null) finishAttempt("Connessione BLE non avviata", "connect_not_started", null, null);
        } catch (SecurityException error) {
            finishAttempt("Connessione BLE non autorizzata", "connect_permission_denied", null, null);
        }
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(@NonNull BluetoothGatt connection, int statusCode, int newState) {
            if (connection != gatt) return;
            if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                setBusyStatus("Connesso · lettura servizi…");
                try {
                    if (!connection.discoverServices())
                        finishAttempt("Lettura servizi non avviata", "service_discovery_not_started", null, statusCode);
                } catch (SecurityException error) {
                    finishAttempt("Accesso ai servizi non autorizzato", "service_discovery_denied", null, statusCode);
                }
            } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED) {
                finishAttempt(statusCode == BluetoothGatt.GATT_SUCCESS ? "Disconnesso" : "Connessione non riuscita (" + statusCode + ")",
                    statusCode == BluetoothGatt.GATT_SUCCESS ? "disconnected" : "connect_failed", null, statusCode);
            }
        }
        @Override public void onServicesDiscovered(@NonNull BluetoothGatt connection, int statusCode) {
            if (connection != gatt) return;
            if (statusCode != BluetoothGatt.GATT_SUCCESS) {
                finishAttempt("Connessione riuscita; lettura servizi non riuscita (" + statusCode + ")",
                    "service_discovery_failed", null, statusCode);
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

    private void stopScan(String fallback) {
        handler.removeCallbacksAndMessages(null);
        try { if (scanner != null) scanner.stopScan(scanCallback); } catch (SecurityException ignored) {}
        if (fallback != null && status.getText().toString().startsWith("Ricerca"))
            finishAttempt(fallback, "not_found", null, null);
    }
    private void finishAttempt(String text, String outcome, Integer batteryPercent, Integer gattStatus) {
        setStatus(text);
        if (!reportWritten.compareAndSet(false, true)) return;
        long startedAt = attemptStartedAtMillis > 0 ? attemptStartedAtMillis : System.currentTimeMillis();
        DriveTestExportManager.exportBipUProbe(this, startedAt, connectionSource,
            outcome, batteryPercent, gattStatus, result -> runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || attemptStartedAtMillis != startedAt) return;
                status.setText(text + (result.success()
                    ? "\nReport salvato su Drive"
                    : result.configured() ? "\nReport Drive non riuscito" : "\nCartella Drive non collegata"));
            }));
    }
    private void setBusyStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(false); }); }
    private void setStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(true); }); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override protected void onDestroy() { stopScan(null); try { if (gatt != null) gatt.close(); } catch (RuntimeException ignored) {} super.onDestroy(); }
}
