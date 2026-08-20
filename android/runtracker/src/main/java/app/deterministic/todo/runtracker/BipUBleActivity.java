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

    static void open(Activity activity) { activity.startActivity(new Intent(activity, BipUBleActivity.class)); }

    private final ActivityResultLauncher<String[]> permissionRequest = registerForActivityResult(
        new ActivityResultContracts.RequestMultiplePermissions(), result -> {
            if (result.values().stream().allMatch(Boolean.TRUE::equals)) connectBondedOrScan();
            else setStatus("Permessi Bluetooth non concessi");
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
        if (adapter == null || !adapter.isEnabled()) { setStatus("Attiva il Bluetooth e riprova"); return; }
        try {
            for (BluetoothDevice device : adapter.getBondedDevices()) {
                if (BipUDeviceSelector.matchesName(device.getName())) {
                    setBusyStatus("Bip U già associato · connessione…");
                    connect(device);
                    return;
                }
            }
        } catch (SecurityException error) {
            setStatus("Accesso ai dispositivi associati non autorizzato");
            return;
        }
        scan(adapter);
    }

    private void scan(BluetoothAdapter adapter) {
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { setStatus("Scanner BLE non disponibile"); return; }
        setBusyStatus("Ricerca Bip U per 12 secondi…");
        try { scanner.startScan(scanCallback); handler.postDelayed(() -> stopScan("Bip U non trovato"), 12_000); }
        catch (SecurityException error) { setStatus("Permesso Bluetooth mancante"); }
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            String name;
            try { name = device.getName(); } catch (SecurityException error) { return; }
            if (!BipUDeviceSelector.matchesName(name)) return;
            stopScan(null); setBusyStatus("Bip U trovato · connessione…"); connect(device);
        }
        @Override public void onScanFailed(int errorCode) { setStatus("Ricerca BLE non riuscita (" + errorCode + ")"); }
    };

    private void connect(BluetoothDevice device) {
        runOnUiThread(() -> probe.setEnabled(false));
        try {
            if (gatt != null) gatt.close();
            gatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        } catch (SecurityException error) {
            setStatus("Connessione BLE non autorizzata");
        }
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(@NonNull BluetoothGatt connection, int statusCode, int newState) {
            if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                setBusyStatus("Connesso · lettura servizi…");
                try { connection.discoverServices(); } catch (SecurityException error) { setStatus("Accesso ai servizi non autorizzato"); }
            } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED) {
                setStatus(statusCode == BluetoothGatt.GATT_SUCCESS ? "Disconnesso" : "Connessione non riuscita (" + statusCode + ")");
            }
        }
        @Override public void onServicesDiscovered(@NonNull BluetoothGatt connection, int statusCode) {
            if (statusCode != BluetoothGatt.GATT_SUCCESS) {
                setStatus("Connessione riuscita; lettura servizi non riuscita (" + statusCode + ")");
                return;
            }
            BluetoothGattService service = connection.getService(BATTERY_SERVICE);
            BluetoothGattCharacteristic level = service == null ? null : service.getCharacteristic(BATTERY_LEVEL);
            if (level == null) { setStatus("Connesso; batteria standard non esposta prima dell’autenticazione"); return; }
            try { connection.readCharacteristic(level); } catch (SecurityException error) { setStatus("Lettura batteria non autorizzata"); }
        }
        @Override public void onCharacteristicRead(@NonNull BluetoothGatt connection, @NonNull BluetoothGattCharacteristic characteristic, byte[] value, int statusCode) {
            if (BATTERY_LEVEL.equals(characteristic.getUuid()) && statusCode == BluetoothGatt.GATT_SUCCESS && value.length > 0) setStatus("Bip U connesso · batteria " + (value[0] & 0xff) + "%");
            else setStatus("Connesso; lettura batteria non riuscita");
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
        if (fallback != null && status.getText().toString().startsWith("Ricerca")) setStatus(fallback);
    }
    private void setBusyStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(false); }); }
    private void setStatus(String text) { runOnUiThread(() -> { status.setText(text); probe.setEnabled(true); }); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override protected void onDestroy() { stopScan(null); try { if (gatt != null) gatt.close(); } catch (RuntimeException ignored) {} super.onDestroy(); }
}
