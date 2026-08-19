package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.TrafficStats;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.Process;
import android.os.SystemClock;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

import org.json.JSONObject;

import java.util.List;
import java.util.UUID;

/** Temporary high-observability experiment. It records features, never coordinates. */
public final class IntensiveDiagnosticService extends Service
        implements SensorEventListener, LocationListener {
    static final String ACTION_START = "app.deterministic.todo.runtracker.INTENSIVE_START";
    static final String ACTION_STOP = "app.deterministic.todo.runtracker.INTENSIVE_STOP";
    private static final String CHANNEL = "movement_intensive_diagnostic";
    private static final int NOTIFICATION_ID = 7412;
    private static final long WINDOW_MS = 5_000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final Window acceleration = new Window();
    private final Window gyroscope = new Window();
    private final Window pressure = new Window();
    private SensorManager sensors;
    private LocationManager locations;
    private IntensiveDiagnosticExperiment.State experiment;
    private String segmentId;
    private long windowStartedElapsed;
    private long windowStartedWall;
    private long windowCpu;
    private long windowRx;
    private long windowTx;
    private long stepEvents;
    private Float counterStart;
    private Float counterLast;
    private int locationCount;
    private Location previousLocation;
    private float locationDistance;
    private float accuracySum;
    private float accuracyMin = Float.MAX_VALUE;
    private float accuracyMax;
    private float speedSum;
    private float speedMax;
    private boolean running;

    private final Runnable flush = new Runnable() {
        @Override public void run() {
            if (!running) return;
            if (!experiment.active(System.currentTimeMillis())) {
                IntensiveDiagnosticExperiment.disable(IntensiveDiagnosticService.this);
                stopCapture();
                return;
            }
            writeWindow();
            resetWindow();
            main.postDelayed(this, WINDOW_MS);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        sensors = (SensorManager) getSystemService(SENSOR_SERVICE);
        locations = (LocationManager) getSystemService(LOCATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(CHANNEL,
            "Diagnostica intensiva movimento", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Esperimento temporaneo con GPS e sensori continui");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            IntensiveDiagnosticExperiment.disable(this);
            stopCapture();
            return START_NOT_STICKY;
        }
        experiment = IntensiveDiagnosticExperiment.state(this);
        if (!experiment.active(System.currentTimeMillis())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
        if (!running) startCapture();
        return START_STICKY;
    }

    private void startCapture() {
        segmentId = UUID.randomUUID().toString();
        try {
            IntensiveDiagnosticStore.beginSegment(this, experiment, segmentId, capabilities());
        } catch (Exception error) {
            recordStatus("start_failed_" + error.getClass().getSimpleName(), 0);
            stopCapture();
            return;
        }
        register(Sensor.TYPE_ACCELEROMETER, SensorManager.SENSOR_DELAY_GAME);
        register(Sensor.TYPE_GYROSCOPE, SensorManager.SENSOR_DELAY_GAME);
        register(Sensor.TYPE_PRESSURE, SensorManager.SENSOR_DELAY_NORMAL);
        register(Sensor.TYPE_STEP_DETECTOR, SensorManager.SENSOR_DELAY_FASTEST);
        register(Sensor.TYPE_STEP_COUNTER, SensorManager.SENSOR_DELAY_NORMAL);
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            == PackageManager.PERMISSION_GRANTED) {
            try { locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1_000, 0f, this,
                Looper.getMainLooper()); }
            catch (RuntimeException error) { recordStatus("location_" + error.getClass().getSimpleName(), 0); }
        }
        running = true;
        resetWindow();
        main.postDelayed(flush, WINDOW_MS);
        recordStatus("running", 0);
    }

    private void register(int type, int delay) {
        Sensor sensor = sensors.getDefaultSensor(type);
        if (sensor != null) sensors.registerListener(this, sensor, delay);
    }

    @Override public void onSensorChanged(SensorEvent event) {
        int type = event.sensor.getType();
        if (type == Sensor.TYPE_ACCELEROMETER && event.values.length >= 3)
            acceleration.add(magnitude(event.values));
        else if (type == Sensor.TYPE_GYROSCOPE && event.values.length >= 3)
            gyroscope.add(magnitude(event.values));
        else if (type == Sensor.TYPE_PRESSURE && event.values.length > 0) pressure.add(event.values[0]);
        else if (type == Sensor.TYPE_STEP_DETECTOR) stepEvents++;
        else if (type == Sensor.TYPE_STEP_COUNTER && event.values.length > 0) {
            if (counterStart == null) counterStart = event.values[0];
            counterLast = event.values[0];
        }
    }

    @Override public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    @Override public void onLocationChanged(Location location) {
        locationCount++;
        accuracySum += location.getAccuracy();
        accuracyMin = Math.min(accuracyMin, location.getAccuracy());
        accuracyMax = Math.max(accuracyMax, location.getAccuracy());
        if (location.hasSpeed()) {
            speedSum += location.getSpeed();
            speedMax = Math.max(speedMax, location.getSpeed());
        }
        if (previousLocation != null) locationDistance += previousLocation.distanceTo(location);
        previousLocation = new Location(location);
    }

    private void writeWindow() {
        long now = System.currentTimeMillis();
        try {
            List<ActivityTimeline.Event> timeline = ActivityTimeline.read(this);
            JSONObject event = new JSONObject().put("schema_version", 1)
                .put("kind", "sensor_window").put("experiment_id", experiment.id())
                .put("segment_id", segmentId).put("started_at_ms", windowStartedWall)
                .put("ended_at_ms", now).put("elapsed_ms", SystemClock.elapsedRealtime() - windowStartedElapsed)
                .put("activity", ActivityTimeline.at(timeline, now))
                .put("accelerometer_magnitude", acceleration.json())
                .put("gyroscope_magnitude", gyroscope.json()).put("pressure_hpa", pressure.json())
                .put("step_detector_events", stepEvents)
                .put("step_counter_delta", counterStart == null || counterLast == null
                    ? JSONObject.NULL : Math.max(0, counterLast - counterStart))
                .put("location", new JSONObject().put("sample_count", locationCount)
                    .put("raw_path_distance_m", locationDistance)
                    .put("accuracy_mean_m", locationCount == 0 ? JSONObject.NULL : accuracySum / locationCount)
                    .put("accuracy_min_m", locationCount == 0 ? JSONObject.NULL : accuracyMin)
                    .put("accuracy_max_m", locationCount == 0 ? JSONObject.NULL : accuracyMax)
                    .put("speed_mean_mps", locationCount == 0 ? JSONObject.NULL : speedSum / locationCount)
                    .put("speed_max_mps", locationCount == 0 ? JSONObject.NULL : speedMax))
                .put("resources", resourceSnapshot())
                .put("device", new JSONObject().put("battery_percent", batteryPercent())
                    .put("power_save", ((PowerManager) getSystemService(POWER_SERVICE)).isPowerSaveMode())
                    .put("interactive", ((PowerManager) getSystemService(POWER_SERVICE)).isInteractive()));
            IntensiveDiagnosticStore.append(this, event);
            recordStatus("running", now);
        } catch (Exception error) { recordStatus("write_failed_" + error.getClass().getSimpleName(), now); }
    }

    private JSONObject resourceSnapshot() throws Exception {
        return new JSONObject()
            .put("cpu_ms", Math.max(0, Process.getElapsedCpuTime() - windowCpu))
            .put("uid_rx_bytes", deltaCounter(TrafficStats.getUidRxBytes(Process.myUid()), windowRx))
            .put("uid_tx_bytes", deltaCounter(TrafficStats.getUidTxBytes(Process.myUid()), windowTx))
            .put("java_heap_used_bytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory());
    }

    private void resetWindow() {
        acceleration.reset(); gyroscope.reset(); pressure.reset();
        stepEvents = 0; counterStart = counterLast; locationCount = 0; locationDistance = 0;
        accuracySum = 0; accuracyMin = Float.MAX_VALUE; accuracyMax = 0; speedSum = 0; speedMax = 0;
        windowStartedElapsed = SystemClock.elapsedRealtime(); windowStartedWall = System.currentTimeMillis();
        windowCpu = Process.getElapsedCpuTime(); windowRx = TrafficStats.getUidRxBytes(Process.myUid());
        windowTx = TrafficStats.getUidTxBytes(Process.myUid());
    }

    private JSONObject capabilities() throws Exception {
        JSONObject json = new JSONObject().put("gps", locations.isProviderEnabled(LocationManager.GPS_PROVIDER));
        int[] types = {Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_PRESSURE,
            Sensor.TYPE_STEP_DETECTOR, Sensor.TYPE_STEP_COUNTER};
        String[] names = {"accelerometer", "gyroscope", "pressure", "step_detector", "step_counter"};
        for (int i = 0; i < types.length; i++) json.put(names[i], sensors.getDefaultSensor(types[i]) != null);
        return json;
    }

    private void stopCapture() {
        running = false; main.removeCallbacks(flush);
        if (sensors != null) sensors.unregisterListener(this);
        if (locations != null) try { locations.removeUpdates(this); } catch (RuntimeException ignored) {}
        IntensiveDiagnosticStore.checkpoint(this);
        recordStatus("stopped", System.currentTimeMillis());
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf();
    }

    private void recordStatus(String status, long lastWindowAt) {
        android.content.SharedPreferences.Editor editor = getSharedPreferences(
            "movement_intensive_status", Context.MODE_PRIVATE).edit().putString("status", status);
        if (lastWindowAt > 0) editor.putLong("last_window_at", lastWindowAt);
        editor.apply();
    }

    private NotificationCompat.Builder notificationBuilder() {
        Intent open = new Intent(this, RunTrackerActivity.class);
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent stop = new Intent(this, IntensiveDiagnosticService.class).setAction(ACTION_STOP);
        PendingIntent stopAction = PendingIntent.getService(this, 2, stop,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle("Diagnostica intensiva attiva")
            .setContentText("GPS e sensori · scadenza automatica tra 7 giorni")
            .setOngoing(true).setOnlyAlertOnce(true).setContentIntent(content)
            .addAction(0, "Termina", stopAction);
    }

    private android.app.Notification notification() { return notificationBuilder().build(); }
    private int batteryPercent() {
        return ((BatteryManager) getSystemService(BATTERY_SERVICE))
            .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
    }
    private static long deltaCounter(long value, long start) {
        return value < 0 || start < 0 ? -1 : Math.max(0, value - start);
    }
    private static double magnitude(float[] values) {
        return Math.sqrt(values[0] * values[0] + values[1] * values[1] + values[2] * values[2]);
    }
    @Nullable @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        if (running) { running = false; main.removeCallbacks(flush); sensors.unregisterListener(this);
            try { locations.removeUpdates(this); } catch (RuntimeException ignored) {}
            IntensiveDiagnosticStore.checkpoint(this); }
        super.onDestroy();
    }

    private static final class Window {
        long count; double sum; double sumSquares; double min = Double.POSITIVE_INFINITY; double max = Double.NEGATIVE_INFINITY;
        void add(double value) { count++; sum += value; sumSquares += value * value; min = Math.min(min, value); max = Math.max(max, value); }
        void reset() { count = 0; sum = 0; sumSquares = 0; min = Double.POSITIVE_INFINITY; max = Double.NEGATIVE_INFINITY; }
        JSONObject json() throws Exception {
            if (count == 0) return new JSONObject().put("count", 0);
            double mean = sum / count;
            return new JSONObject().put("count", count).put("mean", mean)
                .put("stddev", Math.sqrt(Math.max(0, sumSquares / count - mean * mean)))
                .put("min", min).put("max", max);
        }
    }
}
