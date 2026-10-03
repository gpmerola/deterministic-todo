package app.deterministic.todo.runtracker;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.SystemClock;

import androidx.core.content.ContextCompat;
import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.fitness.FitnessLocal;
import com.google.android.gms.fitness.LocalRecordingClient;
import com.google.android.gms.fitness.data.LocalDataType;
import com.google.android.gms.fitness.data.LocalField;
import com.google.android.gms.fitness.request.LocalDataReadRequest;
import com.google.android.gms.tasks.Tasks;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Accountless step subscription; no Fit app, GPS, BLE, cloud or foreground service. */
public final class LocalStepRecording {
    private static final String PREFS = "local_step_recording";
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final AtomicBoolean BUSY = new AtomicBoolean();
    private static volatile long nextRefresh;

    private LocalStepRecording() {}

    public static void schedule(Context context) {
        LocalStepRecordingWorker.schedule(context);
        refreshIfDue(context);
    }

    public static void refreshIfDue(Context context) {
        if (SystemClock.elapsedRealtime() < nextRefresh || !BUSY.compareAndSet(false, true)) return;
        nextRefresh = SystemClock.elapsedRealtime() + 60_000;
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try { collect(app); } finally { BUSY.set(false); }
        });
    }

    /** Serialized across worker and foreground requests; all API waits are bounded. */
    static synchronized void collect(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(context,
            Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            status(prefs, "permission_required");
            return;
        }
        int availability = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(
            context, LocalRecordingClient.LOCAL_RECORDING_CLIENT_MIN_VERSION_CODE);
        if (availability != ConnectionResult.SUCCESS) {
            status(prefs, "play_services_unavailable_" + availability);
            return;
        }
        try {
            status(prefs, "subscribing");
            LocalRecordingClient client = FitnessLocal.getLocalRecordingClient(context);
            // Documented no-op when already subscribed, and restores a revoked subscription.
            Tasks.await(client.subscribe(LocalDataType.TYPE_STEP_COUNT_DELTA), 12, TimeUnit.SECONDS);
            RunDao dao = RunDatabase.get(context).runs();
            LocalStepState state = dao.localStepState();
            if (state == null) {
                ZoneId zone = ZoneId.systemDefault();
                String day = LocalDate.now(zone).toString();
                state = new LocalStepState();
                state.startMillis = LocalStepImportPolicy.nextMinute(System.currentTimeMillis());
                state.legacyDay = day;
                state.legacyZoneId = zone.getId();
                state.legacySteps = Math.max(0, context.getSharedPreferences("phone_daily_steps",
                    Context.MODE_PRIVATE).getLong("steps|" + day + "|" + zone.getId(), 0));
                dao.insertLocalStepState(state);
                state = dao.localStepState();
            }
            long now = System.currentTimeMillis();
            LocalStepImportPolicy.Window window = LocalStepImportPolicy.window(
                state.startMillis, state.importedThroughMillis, now);
            if (window.start() >= window.end()) {
                status(prefs, "awaiting_complete_minute");
                return;
            }
            status(prefs, "reading");
            var request = new LocalDataReadRequest.Builder()
                .aggregate(LocalDataType.TYPE_STEP_COUNT_DELTA)
                .bucketByTime(1, TimeUnit.MINUTES)
                .setTimeRange(window.start(), window.end(), TimeUnit.MILLISECONDS).build();
            var response = Tasks.await(client.readData(request), 12, TimeUnit.SECONDS);
            var minutes = new ArrayList<LocalStepMinute>();
            var seen = new HashSet<Long>();
            String zone = ZoneId.systemDefault().getId();
            for (var bucket : response.getBuckets()) {
                long start = bucket.getStartTime(TimeUnit.MILLISECONDS);
                long end = bucket.getEndTime(TimeUnit.MILLISECONDS);
                // Ignore any API-provided partial boundary bucket; never round its steps.
                if (!LocalStepImportPolicy.valid(start, end, 0, window)) continue;
                if (!seen.add(start)) throw new IllegalStateException("duplicate_bucket");
                long steps = 0;
                var data = bucket.getDataSet(LocalDataType.TYPE_STEP_COUNT_DELTA);
                if (data != null) for (var point : data.getDataPoints()) {
                    int count = point.getValue(LocalField.FIELD_STEPS).asInt();
                    if (count < 0) throw new IllegalStateException("negative_steps");
                    steps = Math.addExact(steps, count);
                }
                LocalStepMinute minute = new LocalStepMinute();
                minute.startMillis = start;
                minute.steps = steps;
                minute.zoneId = zone;
                minute.importedAtMillis = now;
                minutes.add(minute);
            }
            if (minutes.isEmpty()) {
                status(prefs, "subscribed_no_samples");
                return; // No data is not proof of zero steps or a completed import window.
            }
            dao.importLocalStepMinutes(minutes, window.end());
            boolean retentionGap = state.importedThroughMillis > 0
                ? state.importedThroughMillis < window.start() : state.startMillis < window.start();
            prefs.edit().putLong("last_success_ms", now)
                .putBoolean("retention_gap", prefs.getBoolean("retention_gap", false) || retentionGap)
                .putString("status", "subscribed").apply();
        } catch (Exception error) {
            if (error instanceof InterruptedException) Thread.currentThread().interrupt();
            Throwable cause = error.getCause() == null ? error : error.getCause();
            status(prefs, cause instanceof ApiException api ? "api_error_" + api.getStatusCode()
                : "error_" + cause.getClass().getSimpleName());
        }
    }

    static Map<String, Object> diagnostics(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        return Map.of("phone_collection_mode", "local_recording_api",
            "phone_coverage", p.getBoolean("retention_gap", false) ? "retention_gap" : "since_subscription_only",
            "phone_accounting_reason", p.getString("status", "not_started"),
            "phone_last_import_ms", p.getLong("last_success_ms", 0));
    }

    public static Map<String, Object> statusValues(Context context) { return diagnostics(context); }

    private static void status(SharedPreferences prefs, String value) {
        prefs.edit().putString("status", value).apply();
    }
}
