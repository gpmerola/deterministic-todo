package app.deterministic.todo.runtracker;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;

import androidx.core.content.ContextCompat;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Reads Android's cumulative hardware counter without depending on Health Connect. */
public final class PhoneDailyMovementGateway {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final long TIMEOUT_MS = 4_000;
    private static final String PREFS = "phone_daily_steps";

    private PhoneDailyMovementGateway() {}

    public interface Callback {
        void onSuccess(DailyMovement movement, long phoneSteps, long bipSteps, String fusionSource);
        void onPermissionRequired();
        void onUnavailable();
        void onError();
    }

    public static void refreshToday(Context context, Callback callback) {
        Context app = context.getApplicationContext();
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(app,
            Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            callback.onPermissionRequired();
            return;
        }
        SensorManager manager = (SensorManager) app.getSystemService(Context.SENSOR_SERVICE);
        Sensor sensor = manager == null ? null : manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
        if (manager == null || sensor == null) {
            callback.onUnavailable();
            return;
        }
        Handler main = new Handler(Looper.getMainLooper());
        AtomicBoolean completed = new AtomicBoolean(false);
        final SensorEventListener[] holder = new SensorEventListener[1];
        Runnable timeout = () -> {
            if (completed.compareAndSet(false, true)) {
                manager.unregisterListener(holder[0]);
                callback.onError();
            }
        };
        holder[0] = new SensorEventListener() {
            @Override public void onSensorChanged(SensorEvent event) {
                if (event.values.length == 0 || !completed.compareAndSet(false, true)) return;
                manager.unregisterListener(this);
                main.removeCallbacks(timeout);
                float raw = event.values[0];
                IO.execute(() -> persistAndCombine(app, raw, callback, main));
            }
            @Override public void onAccuracyChanged(Sensor sensor, int accuracy) {}
        };
        if (!manager.registerListener(holder[0], sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            callback.onUnavailable();
            return;
        }
        main.postDelayed(timeout, TIMEOUT_MS);
    }

    private static void persistAndCombine(Context app, float raw, Callback callback, Handler main) {
        try {
            if (!Float.isFinite(raw) || raw < 0) throw new IllegalArgumentException("invalid counter");
            long now = System.currentTimeMillis();
            ZoneId zone = ZoneId.systemDefault();
            LocalDate day = Instant.ofEpochMilli(now).atZone(zone).toLocalDate();
            long start = day.atStartOfDay(zone).toInstant().toEpochMilli();
            long end = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli();
            String dayKey = day + "|" + zone.getId();
            SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            int boot = Settings.Global.getInt(app.getContentResolver(), Settings.Global.BOOT_COUNT, -1);
            int lastBoot = prefs.getInt("last_boot", Integer.MIN_VALUE);
            float lastRaw = prefs.getFloat("last_raw", -1f);
            long phone = prefs.getLong("steps|" + dayKey, 0);
            long delta = 0;
            if (boot == lastBoot && lastRaw >= 0 && raw >= lastRaw) {
                delta = (long) Math.floor(raw - lastRaw);
            } else if (lastRaw < 0 && now - SystemClock.elapsedRealtime() >= start) {
                // A boot that began today makes the cumulative reading today's exact baseline.
                delta = (long) Math.floor(raw);
            }
            phone += Math.max(0, delta);
            prefs.edit().putInt("last_boot", boot).putFloat("last_raw", raw)
                .putString("last_day", dayKey).putLong("steps|" + dayKey, phone)
                .putLong("last_sample_ms", now).apply();

            RunDao dao = RunDatabase.get(app).runs();
            long bip = Math.max(0, dao.bipUSteps(start, end));
            DailyMovementFusion.Result fused = DailyMovementFusion.combine(phone, bip);
            SharedPreferences profile = app.getSharedPreferences("movement_profile", Context.MODE_PRIVATE);
            double stride = profile.getFloat("walking_stride_meters",
                (float) MovementEstimate.DEFAULT_STRIDE_METERS);
            double weight = profile.getFloat("weight_kg", (float) MovementEstimate.DEFAULT_WEIGHT_KG);
            MovementEstimate estimate = MovementEstimate.fromSteps(fused.steps(), stride, weight);
            DailyMovement row = new DailyMovement();
            row.day = day.toString();
            row.zoneId = zone.getId();
            row.source = "local_conservative_" + fused.source();
            row.steps = fused.steps();
            row.estimatedDistanceMeters = estimate.distanceMeters();
            row.estimatedActiveCalories = estimate.activeCalories();
            row.updatedAtMillis = now;
            dao.upsertDailyMovement(row);
            long finalPhone = phone;
            main.post(() -> callback.onSuccess(row, finalPhone, bip, fused.source()));
        } catch (Exception ignored) {
            main.post(callback::onError);
        }
    }
}
