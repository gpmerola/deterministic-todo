package app.deterministic.todo.runtracker;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothStatusCodes;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bounded, read-only Bip U history import usable without an Activity. */
final class BipUAutomaticSyncClient {
    interface Completion { void finished(String outcome); }

    private static final UUID AUTH_SERVICE = UUID.fromString("0000fee1-0000-1000-8000-00805f9b34fb");
    private static final UUID AUTH = UUID.fromString("00000009-0000-3512-2118-0009af100700");
    private static final UUID ACTIVITY_SERVICE = UUID.fromString("0000fee0-0000-1000-8000-00805f9b34fb");
    private static final UUID ACTIVITY_CONTROL = UUID.fromString("00000004-0000-3512-2118-0009af100700");
    private static final UUID ACTIVITY_DATA = UUID.fromString("00000005-0000-3512-2118-0009af100700");
    private static final UUID CLIENT_CONFIGURATION = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final long SCAN_TIMEOUT_MS = 12_000;
    private static final long SYNC_TIMEOUT_MS = 90_000;

    private enum Stage { AUTH_NOTIFY, AUTH_CHALLENGE, AUTH_ENCRYPTED, DATA_NOTIFY,
        CONTROL_NOTIFY, REQUEST, FETCH }

    private final Context context;
    private final Completion completion;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean finished = new AtomicBoolean();
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic auth;
    private BluetoothGattCharacteristic control;
    private BluetoothGattCharacteristic data;
    private byte[] authKey;
    private Stage stage;
    private BipUActivityProtocol.PacketBuffer buffer;
    private BipUActivityProtocol.Metadata metadata;
    private BipUBackfillPolicy.Request request;

    BipUAutomaticSyncClient(Context context, Completion completion) {
        this.context = context.getApplicationContext();
        this.completion = completion;
    }

    void start() {
        if (!BipUSyncCoordinator.tryAcquire()) { completion.finished("already_running"); return; }
        BipUSyncDebugState.started(context, System.currentTimeMillis());
        if (!hasPermissions()) { finish("permission_required", 0, 0, 0); return; }
        try { authKey = new SecureAuthKeyStore(context).read(); }
        catch (Exception error) { finish("key_unavailable", 0, 0, 0); return; }
        if (authKey == null || authKey.length != 16) { finish("key_missing", 0, 0, 0); return; }
        BluetoothManager manager = context.getSystemService(BluetoothManager.class);
        BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
        if (adapter == null || !adapter.isEnabled()) { finish("bluetooth_disabled", 0, 0, 0); return; }
        handler.postDelayed(() -> finish("automatic_timeout", 0, 0, 0), SYNC_TIMEOUT_MS);
        try {
            for (BluetoothDevice device : adapter.getBondedDevices()) {
                if (BipUDeviceSelector.matchesName(device.getName())) { connect(device); return; }
            }
            scan(adapter);
        } catch (SecurityException error) { finish("permission_required", 0, 0, 0); }
    }

    private boolean hasPermissions() {
        if (Build.VERSION.SDK_INT >= 31)
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
                && ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void scan(BluetoothAdapter adapter) {
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { finish("scanner_unavailable", 0, 0, 0); return; }
        try {
            scanner.startScan(scanCallback);
            handler.postDelayed(() -> finish("not_found", 0, 0, 0), SCAN_TIMEOUT_MS);
        } catch (SecurityException error) { finish("permission_required", 0, 0, 0); }
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override public void onScanResult(int callbackType, ScanResult result) {
            try {
                if (!BipUDeviceSelector.matchesName(result.getDevice().getName())) return;
                stopScan();
                connect(result.getDevice());
            } catch (SecurityException ignored) {}
        }
        @Override public void onScanFailed(int errorCode) { finish("scan_failed", 0, 0, 0); }
    };

    private void connect(BluetoothDevice device) {
        try {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
            if (gatt == null) finish("connect_not_started", 0, 0, 0);
        } catch (SecurityException error) { finish("permission_required", 0, 0, 0); }
    }

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(@NonNull BluetoothGatt connection, int status, int newState) {
            if (connection != gatt) return;
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                try { if (!connection.discoverServices()) finish("service_discovery_not_started", 0, 0, 0); }
                catch (SecurityException error) { finish("permission_required", 0, 0, 0); }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED)
                finish(status == BluetoothGatt.GATT_SUCCESS ? "disconnected" : "connect_failed", 0, 0, 0);
        }

        @Override public void onServicesDiscovered(@NonNull BluetoothGatt connection, int status) {
            if (connection != gatt || status != BluetoothGatt.GATT_SUCCESS) {
                finish("service_discovery_failed", 0, 0, 0); return;
            }
            BluetoothGattService service = connection.getService(AUTH_SERVICE);
            auth = service == null ? null : service.getCharacteristic(AUTH);
            if (auth == null) { finish("auth_service_unavailable", 0, 0, 0); return; }
            stage = Stage.AUTH_NOTIFY;
            if (!enableNotifications(connection, auth)) finish("auth_notifications_unavailable", 0, 0, 0);
        }

        @Override public void onDescriptorWrite(@NonNull BluetoothGatt connection,
                                                @NonNull BluetoothGattDescriptor descriptor, int status) {
            if (connection != gatt || status != BluetoothGatt.GATT_SUCCESS) {
                finish("notification_setup_failed", 0, 0, 0); return;
            }
            if (stage == Stage.AUTH_NOTIFY) {
                stage = Stage.AUTH_CHALLENGE;
                if (!write(connection, auth, HuamiAuthProtocol.requestChallenge()))
                    finish("auth_challenge_write_failed", 0, 0, 0);
            } else if (stage == Stage.DATA_NOTIFY) {
                stage = Stage.CONTROL_NOTIFY;
                if (!enableNotifications(connection, control)) finish("activity_control_notifications_unavailable", 0, 0, 0);
            } else if (stage == Stage.CONTROL_NOTIFY) {
                stage = Stage.REQUEST;
                buffer = new BipUActivityProtocol.PacketBuffer();
                requestHistory(connection);
            }
        }

        @Override public void onCharacteristicWrite(@NonNull BluetoothGatt connection,
                                                     @NonNull BluetoothGattCharacteristic characteristic, int status) {
            if (connection != gatt || status != BluetoothGatt.GATT_SUCCESS)
                finish("activity_write_rejected", 0, 0, 0);
        }

        @Override public void onCharacteristicChanged(@NonNull BluetoothGatt connection,
                                                       @NonNull BluetoothGattCharacteristic characteristic, byte[] value) {
            if (connection != gatt) return;
            if (AUTH.equals(characteristic.getUuid())) handleAuth(connection, value);
            else if (ACTIVITY_DATA.equals(characteristic.getUuid()) && stage == Stage.FETCH) {
                if (buffer == null || !buffer.append(value)) finish("activity_packet_gap", 0, 0, 0);
            } else if (ACTIVITY_CONTROL.equals(characteristic.getUuid())) handleControl(connection, value);
        }

        @SuppressWarnings("deprecation") @Override public void onCharacteristicChanged(
            @NonNull BluetoothGatt connection, @NonNull BluetoothGattCharacteristic characteristic) {
            onCharacteristicChanged(connection, characteristic, characteristic.getValue());
        }
    };

    private void handleAuth(BluetoothGatt connection, byte[] value) {
        try {
            HuamiAuthProtocol.Result result = HuamiAuthProtocol.handle(value, authKey);
            if (result.kind() == HuamiAuthProtocol.Kind.CHALLENGE) {
                stage = Stage.AUTH_ENCRYPTED;
                if (!write(connection, auth, result.command())) finish("auth_response_write_failed", 0, 0, 0);
            } else if (result.kind() == HuamiAuthProtocol.Kind.AUTHENTICATED) {
                authKey = null;
                BluetoothGattService service = connection.getService(ACTIVITY_SERVICE);
                control = service == null ? null : service.getCharacteristic(ACTIVITY_CONTROL);
                data = service == null ? null : service.getCharacteristic(ACTIVITY_DATA);
                if (control == null || data == null) { finish("activity_service_unavailable", 0, 0, 0); return; }
                stage = Stage.DATA_NOTIFY;
                if (!enableNotifications(connection, data)) finish("activity_data_notifications_unavailable", 0, 0, 0);
            } else if (result.kind() == HuamiAuthProtocol.Kind.FAILED)
                finish("authentication_failed", 0, 0, 0);
        } catch (Exception error) { finish("authentication_crypto_failed", 0, 0, 0); }
    }

    private void requestHistory(BluetoothGatt connection) {
        long now = System.currentTimeMillis();
        new Thread(() -> {
            Long latest = RunDatabase.get(context).runs().latestBipUSampleTimestamp();
            BipUBackfillPolicy.Request planned = BipUBackfillPolicy.request(now, latest);
            handler.post(() -> {
                if (finished.get() || connection != gatt || stage != Stage.REQUEST) return;
                request = planned;
                Instant since = Instant.ofEpochMilli(planned.sinceMillis());
                if (!write(connection, control, BipUActivityProtocol.requestSince(since,
                    ZoneId.systemDefault().getRules().getOffset(since))))
                    finish("activity_request_failed", 0, 0, 0);
            });
        }, "bip-auto-plan").start();
    }

    private void handleControl(BluetoothGatt connection, byte[] value) {
        BipUActivityProtocol.Metadata parsed = BipUActivityProtocol.parseMetadata(value);
        if (parsed != null) {
            metadata = parsed;
            if (parsed.expectedBytes() == 0) { finish("activity_empty", 0, 0, 0); return; }
            stage = Stage.FETCH;
            if (!write(connection, control, new byte[] {BipUActivityProtocol.FETCH}))
                finish("activity_fetch_failed", 0, 0, 0);
        } else if (BipUActivityProtocol.isFetchComplete(value) && stage == Stage.FETCH) persist();
    }

    private void persist() {
        if (metadata == null || buffer == null) { finish("activity_metadata_missing", 0, 0, 0); return; }
        byte[] payload = buffer.bytes();
        long expected = metadata.expectedBytes();
        if (payload.length != expected && (expected > Integer.MAX_VALUE / BipUActivityProtocol.SAMPLE_BYTES
            || payload.length != expected * BipUActivityProtocol.SAMPLE_BYTES)) {
            finish("activity_length_mismatch", 0, 0, 0); return;
        }
        final List<BipUActivitySample> samples;
        try { samples = BipUActivityProtocol.decode(payload, metadata.firstTimestampMillis(), System.currentTimeMillis()); }
        catch (IllegalArgumentException error) { finish("activity_payload_invalid", 0, 0, 0); return; }
        new Thread(() -> {
            List<Long> ids = RunDatabase.get(context).runs().insertBipUActivitySamples(samples);
            long inserted = ids.stream().filter(id -> id != null && id != -1L).count();
            long steps = samples.stream().mapToLong(sample -> sample.steps).sum();
            finish("activity_sync_success", samples.size(), inserted, steps);
        }, "bip-auto-store").start();
    }

    private boolean enableNotifications(BluetoothGatt connection, BluetoothGattCharacteristic characteristic) {
        try {
            if (!connection.setCharacteristicNotification(characteristic, true)) return false;
            BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION);
            if (descriptor == null) return false;
            if (Build.VERSION.SDK_INT >= 33)
                return connection.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS;
            descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            return connection.writeDescriptor(descriptor);
        } catch (SecurityException error) { return false; }
    }

    private boolean write(BluetoothGatt connection, BluetoothGattCharacteristic characteristic, byte[] value) {
        try {
            int type = GattWritePolicy.select(characteristic.getProperties(), characteristic.getWriteType(), characteristic == auth);
            if (Build.VERSION.SDK_INT >= 33)
                return connection.writeCharacteristic(characteristic, value, type) == BluetoothStatusCodes.SUCCESS;
            characteristic.setWriteType(type); characteristic.setValue(value);
            return connection.writeCharacteristic(characteristic);
        } catch (SecurityException error) { return false; }
    }

    private void finish(String outcome, long samples, long inserted, long steps) {
        if (!finished.compareAndSet(false, true)) return;
        handler.removeCallbacksAndMessages(null);
        stopScan();
        BluetoothGatt connection = gatt; gatt = null; authKey = null;
        try { if (connection != null) connection.close(); } catch (RuntimeException ignored) {}
        BipUSyncDebugState.automaticFinished(context, outcome, samples, inserted, steps,
            request == null ? 0 : request.requestedHours());
        BipUSyncCoordinator.release();
        completion.finished(outcome);
    }

    private void stopScan() {
        try { if (scanner != null) scanner.stopScan(scanCallback); } catch (SecurityException ignored) {}
        scanner = null;
    }
}
