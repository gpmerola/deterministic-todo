package app.deterministic.todo.runtracker;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.TrafficStats;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Debug;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import android.provider.DocumentsContract;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

final class DriveTestExportManager {
    private static final String PREFS = "movement_drive_export";
    private static final String TREE_URI = "tree_uri";
    private static final String LAST_STATUS = "last_status";
    private static final String LAST_ERROR = "last_error";
    private static final String LAST_EXPORTED_AT = "last_exported_at";
    private static final String COMPARISON_STATUS = "comparison_status";
    private static final String COMPARISON_SUMMARY = "comparison_summary";
    private static final long HEALTH_TIMEOUT_MILLIS = 8_000;
    private DriveTestExportManager() {}

    record ExportResult(boolean configured, boolean success, String code) {}
    interface Completion { void onComplete(ExportResult result); }

    static void setFolder(Context context, Uri uri, int resultFlags) {
        int takeFlags = resultFlags & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        if ((takeFlags & Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == 0) {
            throw new SecurityException("write permission missing");
        }
        context.getContentResolver().takePersistableUriPermission(uri,
            takeFlags);
        if (!canReadFolder(context, uri)) throw new SecurityException("folder unavailable");
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(TREE_URI, uri.toString())
            .putString(LAST_STATUS, "ready")
            .remove(LAST_ERROR)
            .apply();
    }

    static boolean isConfigured(Context context) { return tree(context) != null; }

    static void captureStart(Context context, long id) {
        android.content.SharedPreferences.Editor e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        e.putLong(id + ".elapsed", android.os.SystemClock.elapsedRealtime());
        e.putLong(id + ".cpu", Process.getElapsedCpuTime());
        e.putLong(id + ".rx", TrafficStats.getUidRxBytes(Process.myUid()));
        e.putLong(id + ".tx", TrafficStats.getUidTxBytes(Process.myUid()));
        e.putInt(id + ".battery", battery(context));
        e.remove(id + ".direct_step_timeline");
        e.apply();
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(id + ".steps", m.steps).apply(); }
            public void onPermissionRequired() {} public void onUnavailable() {} public void onError() {}
        });
    }

    static void captureDirectSteps(Context context, long id, long steps, String sensorStatus) {
        if (id == 0) return;
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(id + ".direct_steps", Math.max(0, steps))
            .putString(id + ".direct_step_status", sensorStatus)
            .apply();
    }

    static long directSteps(Context context, long id) {
        return Math.max(0, context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(id + ".direct_steps", 0));
    }

    static DirectStepTimeline directStepTimeline(Context context, long id) {
        return DirectStepTimeline.decode(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(id + ".direct_step_timeline", null));
    }

    static void captureDirectStepTimeline(Context context, long id, DirectStepTimeline timeline) {
        if (id == 0 || timeline == null) return;
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(id + ".direct_step_timeline", timeline.encode()).apply();
    }

    static void captureGoogleFitComparison(Context context, long id,
                                           HealthConnectGateway.GoogleFitComparison comparison) {
        if (id == 0 || comparison == null) return;
        android.content.SharedPreferences.Editor editor = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(id + ".fit_observed_at", System.currentTimeMillis())
            .putLong(id + ".fit_local_steps", comparison.getLocalSteps())
            .putFloat(id + ".fit_local_distance_m", (float) comparison.getLocalDistanceMeters());
        if (comparison.getSteps() != null) editor.putLong(id + ".fit_steps", comparison.getSteps());
        else editor.remove(id + ".fit_steps");
        if (comparison.getDistanceMeters() != null) editor.putFloat(id + ".fit_distance_m", comparison.getDistanceMeters().floatValue());
        else editor.remove(id + ".fit_distance_m");
        if (comparison.getActiveCalories() != null) editor.putFloat(id + ".fit_active_calories", comparison.getActiveCalories().floatValue());
        else editor.remove(id + ".fit_active_calories");
        String fitDistance = comparison.getDistanceMeters() == null ? "—" :
            String.format(java.util.Locale.ITALY, "%.3f km", comparison.getDistanceMeters() / 1000);
        String distanceDelta = comparison.getDistanceMeters() == null || comparison.getDistanceMeters() <= 0 ? "—" :
            String.format(java.util.Locale.ITALY, "%+.1f%%", 100 * (comparison.getLocalDistanceMeters() - comparison.getDistanceMeters()) / comparison.getDistanceMeters());
        String fitSteps = comparison.getSteps() == null ? "—" : String.format(java.util.Locale.ITALY, "%,d", comparison.getSteps());
        String stepDelta = comparison.getSteps() == null || comparison.getSteps() <= 0 ? "—" :
            String.format(java.util.Locale.ITALY, "%+.1f%%", 100.0 * (comparison.getLocalSteps() - comparison.getSteps()) / comparison.getSteps());
        editor.putString(COMPARISON_SUMMARY, String.format(java.util.Locale.ITALY,
            "Google Fit %s · %s passi\nTodo %.3f km (%s) · %,d passi (%s)",
            fitDistance, fitSteps, comparison.getLocalDistanceMeters() / 1000,
            distanceDelta, comparison.getLocalSteps(), stepDelta));
        editor.apply();
    }

    static void setComparisonStatus(Context context, String status) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(COMPARISON_STATUS, status).apply();
    }

    static void captureComparisonAttempt(Context context, long id, String status, int attempts) {
        captureComparisonAttempt(context, id, status, attempts, null);
    }

    static void captureComparisonAttempt(Context context, long id, String status, int attempts,
                                         String errorCode) {
        android.content.SharedPreferences.Editor editor = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(COMPARISON_STATUS, status)
            .putString(id + ".comparison_status", status)
            .putInt(id + ".comparison_attempts", attempts)
            .putLong(id + ".comparison_last_attempt_at", System.currentTimeMillis());
        if (errorCode == null) editor.remove(id + ".comparison_error_code");
        else editor.putString(id + ".comparison_error_code", errorCode);
        editor.apply();
    }

    static String comparisonStatus(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(COMPARISON_STATUS, "idle");
    }

    static String comparisonStatus(Context context, long sessionId) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(sessionId + ".comparison_status", "not_scheduled");
    }

    static String comparisonSummary(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(COMPARISON_SUMMARY, "Confronto completato e salvato su Drive");
    }

    static String status(Context context) {
        android.content.SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String status = p.getString(LAST_STATUS, isConfigured(context) ? "ready" : "not_configured");
        if ("success".equals(status)) return "Ultimo caricamento Drive completato";
        if ("exporting".equals(status)) return "Export Drive in corso…";
        if ("failed".equals(status)) return "Ultimo export Drive non riuscito · " + p.getString(LAST_ERROR, "errore_sconosciuto");
        if ("ready".equals(status)) return "Cartella Drive pronta · nessun export completato";
        return "Cartella Drive non collegata";
    }

    static void finish(Context context, RunSession session, List<TrackPoint> points, Completion completion) {
        StrideCalibrator.record(context, session, directSteps(context, session.id));
        if (!isConfigured(context)) {
            completion.onComplete(new ExportResult(false, false, "not_configured"));
            return;
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(LAST_STATUS, "exporting").apply();
        AtomicBoolean exportStarted = new AtomicBoolean(false);
        class ExportStarter {
            void start(Long stepsEnd, String healthStatus) {
                if (!exportStarted.compareAndSet(false, true)) return;
                new Thread(() -> completion.onComplete(write(context, session, points, stepsEnd, healthStatus)),
                    "movement-drive-export").start();
            }
        }
        ExportStarter starter = new ExportStarter();
        new Handler(Looper.getMainLooper()).postDelayed(
            () -> starter.start(null, "timeout"), HEALTH_TIMEOUT_MILLIS
        );
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { starter.start(m.steps, "fresh"); }
            public void onPermissionRequired() { starter.start(null, "permission_required"); }
            public void onUnavailable() { starter.start(null, "unavailable"); }
            public void onError() { starter.start(null, "error"); }
        });
    }

    static void exportComparison(Context context, RunSession session, Completion completion) {
        new Thread(() -> completion.onComplete(writeComparison(context, session)),
            "movement-drive-comparison").start();
    }

    private static ExportResult writeComparison(Context c, RunSession s) {
        if (!isConfigured(c)) return new ExportResult(false, false, "not_configured");
        try {
            android.content.SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            long observedAt = p.getLong(s.id + ".fit_observed_at", 0);
            if (observedAt <= 0) return new ExportResult(true, false, "comparison_missing");
            String base = String.format(java.util.Locale.ROOT, "%d_%s_session-%06d",
                s.startedAtMillis, s.activityType, s.id);
            JSONObject fit = new JSONObject()
                .put("schema_version", 1)
                .put("session_id", s.id)
                .put("observed_at_ms", observedAt)
                .put("started_at_ms", s.startedAtMillis)
                .put("ended_at_ms", s.endedAtMillis)
                .put("fit_steps", p.contains(s.id + ".fit_steps") ? p.getLong(s.id + ".fit_steps", 0) : JSONObject.NULL)
                .put("fit_distance_m", p.contains(s.id + ".fit_distance_m") ? p.getFloat(s.id + ".fit_distance_m", 0) : JSONObject.NULL)
                .put("fit_active_calories", p.contains(s.id + ".fit_active_calories") ? p.getFloat(s.id + ".fit_active_calories", 0) : JSONObject.NULL)
                .put("local_steps", p.getLong(s.id + ".fit_local_steps", 0))
                .put("local_distance_m", p.getFloat(s.id + ".fit_local_distance_m", 0));
            writeNewFile(c, base + "_comparison-" + observedAt + ".json",
                "application/json", fit.toString(2));
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            String code = "drive_comparison_failed_" + error.getClass().getSimpleName();
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "failed").putString(LAST_ERROR, code).apply();
            return new ExportResult(true, false, code);
        }
    }

    static ExportResult writePassiveAudit(Context c, HealthConnectGateway.PassiveAudit audit) {
        if (!isConfigured(c)) return new ExportResult(false, false, "not_configured");
        try {
            android.content.SharedPreferences profile = c.getSharedPreferences("movement_profile", Context.MODE_PRIVATE);
            double stride = profile.getFloat("walking_stride_meters",
                (float) MovementEstimate.DEFAULT_STRIDE_METERS);
            double runningStride = profile.getFloat("running_stride_meters",
                (float) MixedMovementEstimate.DEFAULT_RUNNING_STRIDE_METERS);
            double weight = profile.getFloat("weight_kg", (float) MovementEstimate.DEFAULT_WEIGHT_KG);
            android.content.SharedPreferences classifier = c.getSharedPreferences(
                "movement_activity_timeline", Context.MODE_PRIVATE);
            MixedMovementEstimate estimate = MixedMovementEstimate.calculate(
                audit.getWalkingSteps(), audit.getRunningSteps(), audit.getUnknownSteps(),
                audit.getExcludedSteps(), stride, runningStride, weight);
            JSONObject json = new JSONObject()
                .put("schema_version", 2)
                .put("kind", "passive_daily_audit")
                .put("day", audit.getDay())
                .put("zone_id", audit.getZoneId())
                .put("observed_at_ms", System.currentTimeMillis())
                .put("activity_classifier", new JSONObject()
                    .put("status", classifier.getString("registration_status", "unknown"))
                    .put("status_observed_at_ms", classifier.contains("registration_observed_at_ms")
                        ? classifier.getLong("registration_observed_at_ms", 0) : JSONObject.NULL)
                    .put("timeline_events", ActivityTimeline.read(c).size()))
                .put("todo", new JSONObject()
                    .put("steps", audit.getAllSteps())
                    .put("estimated_distance_m", estimate.distanceMeters())
                    .put("estimated_active_calories", estimate.activeCalories())
                    .put("walking_steps", estimate.walkingSteps())
                    .put("running_steps", estimate.runningSteps())
                    .put("unknown_steps", estimate.unknownSteps())
                    .put("excluded_vehicle_bicycle_still_steps", estimate.excludedSteps())
                    .put("walking_stride_m", stride)
                    .put("running_stride_m", runningStride)
                    .put("weight_kg", weight))
                .put("health_connect_all_sources", new JSONObject()
                    .put("distance_m", audit.getAllDistanceMeters() == null ? JSONObject.NULL : audit.getAllDistanceMeters())
                    .put("active_calories", audit.getAllActiveCalories() == null ? JSONObject.NULL : audit.getAllActiveCalories()))
                .put("google_fit", new JSONObject()
                    .put("steps", audit.getFitSteps() == null ? JSONObject.NULL : audit.getFitSteps())
                    .put("distance_m", audit.getFitDistanceMeters() == null ? JSONObject.NULL : audit.getFitDistanceMeters())
                    .put("active_calories", audit.getFitActiveCalories() == null ? JSONObject.NULL : audit.getFitActiveCalories()));
            writeNewFile(c, "daily_audit_" + audit.getDay() + ".json", "application/json", json.toString(2));
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            return new ExportResult(true, false, "drive_audit_failed_" + error.getClass().getSimpleName());
        }
    }

    private static ExportResult write(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd, String healthStatus) {
        android.content.SharedPreferences.Editor status = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        try {
            String base = String.format(java.util.Locale.ROOT, "%d_%s_session-%06d", s.startedAtMillis, s.activityType, s.id);
            writeFile(c, base + ".gpx", "application/gpx+xml", GpxExporter.export(s, points));
            writeFile(c, base + "_diagnostics.json", "application/json", diagnostics(c, s, points, stepsEnd, healthStatus).toString(2));
            status.putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            String code = "drive_write_failed_" + error.getClass().getSimpleName();
            status.putString(LAST_STATUS, "failed").putString(LAST_ERROR, code).apply();
            return new ExportResult(true, false, code);
        }
    }

    private static JSONObject diagnostics(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd, String healthStatus) throws Exception {
        android.content.SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSONObject reasons = new JSONObject(); JSONArray samples = new JSONArray(); int accepted = 0; double accuracySum = 0; float accuracyMax = 0;
        for (TrackPoint x : points) {
            if (x.accepted) accepted++; else reasons.put(x.rejectionReason, reasons.optInt(x.rejectionReason) + 1);
            accuracySum += x.accuracyMeters; accuracyMax = Math.max(accuracyMax, x.accuracyMeters);
            samples.put(new JSONObject().put("time_ms", x.timestampMillis).put("lat", x.latitude).put("lon", x.longitude)
                .put("accuracy_m", x.accuracyMeters).put("accepted", x.accepted).put("reason", x.rejectionReason)
                .put("distance_total_m", x.accumulatedDistanceMeters));
        }
        long elapsed0 = p.getLong(s.id + ".elapsed", 0), cpu0 = p.getLong(s.id + ".cpu", 0);
        long rx0 = p.getLong(s.id + ".rx", -1), tx0 = p.getLong(s.id + ".tx", -1), steps0 = p.getLong(s.id + ".steps", -1);
        long directSteps = p.getLong(s.id + ".direct_steps", -1);
        String directStepStatus = p.getString(s.id + ".direct_step_status", "not_recorded");
        JSONArray directStepSamples = new JSONArray();
        for (DirectStepTimeline.Sample sample : directStepTimeline(c, s.id).snapshot()) {
            directStepSamples.put(new JSONObject().put("time_ms", sample.timeMillis())
                .put("steps", sample.steps()).put("status", sample.status()));
        }
        long exportedAt = System.currentTimeMillis();
        long fitObservedAt = p.getLong(s.id + ".fit_observed_at", -1);
        String automationStatus = p.getString(s.id + ".comparison_status", "not_scheduled");
        JSONObject fit = new JSONObject()
            .put("status", fitObservedAt < 0 ? "not_compared" : "available")
            .put("automation_status", automationStatus)
            .put("attempt_count", p.getInt(s.id + ".comparison_attempts", 0))
            .put("last_attempt_at_ms", p.contains(s.id + ".comparison_last_attempt_at")
                ? p.getLong(s.id + ".comparison_last_attempt_at", 0) : JSONObject.NULL);
        fit.put("error_code", p.contains(s.id + ".comparison_error_code")
            ? p.getString(s.id + ".comparison_error_code", "health_error_unknown")
            : JSONObject.NULL);
        if (fitObservedAt >= 0) {
            fit.put("observed_at_ms", fitObservedAt)
                .put("steps", p.contains(s.id + ".fit_steps") ? p.getLong(s.id + ".fit_steps", 0) : JSONObject.NULL)
                .put("distance_m", p.contains(s.id + ".fit_distance_m") ? p.getFloat(s.id + ".fit_distance_m", 0) : JSONObject.NULL)
                .put("active_calories", p.contains(s.id + ".fit_active_calories") ? p.getFloat(s.id + ".fit_active_calories", 0) : JSONObject.NULL)
                .put("local_steps", p.getLong(s.id + ".fit_local_steps", 0))
                .put("local_distance_m", p.getFloat(s.id + ".fit_local_distance_m", 0));
        }
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo(); ((ActivityManager)c.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
        return new JSONObject().put("schema_version", 1).put("session_id", s.id).put("activity", s.activityType)
            .put("started_at_ms", s.startedAtMillis).put("ended_at_ms", s.endedAtMillis).put("duration_ms", s.endedAtMillis - s.startedAtMillis)
            .put("exported_at_ms", exportedAt)
            .put("distance_m", s.distanceMeters).put("steps_start_daily", steps0 < 0 ? JSONObject.NULL : steps0)
            .put("steps_end_daily", stepsEnd == null ? JSONObject.NULL : stepsEnd)
            .put("steps_end_observed_at_ms", stepsEnd == null ? JSONObject.NULL : exportedAt)
            .put("steps_delta", stepsEnd == null || steps0 < 0 || stepsEnd < steps0 ? JSONObject.NULL : stepsEnd - steps0)
            .put("steps_end_status", healthStatus)
            .put("session_steps_direct", directSteps < 0 ? JSONObject.NULL : directSteps)
            .put("session_steps_direct_status", directStepStatus)
            .put("session_steps_direct_samples", directStepSamples)
            .put("google_fit_comparison", fit)
            .put("gps", new JSONObject().put("samples", points.size()).put("accepted", accepted).put("rejected", points.size()-accepted)
                .put("rejection_reasons", reasons).put("accuracy_mean_m", points.isEmpty()?JSONObject.NULL:accuracySum/points.size()).put("accuracy_max_m", accuracyMax))
            .put("resources", new JSONObject().put("battery_start_pct", p.getInt(s.id + ".battery", -1)).put("battery_end_pct", battery(c))
                .put("wall_elapsed_ms", monotonicDelta(elapsed0, android.os.SystemClock.elapsedRealtime()))
                .put("process_cpu_ms", monotonicDelta(cpu0, Process.getElapsedCpuTime())).put("process_pss_kb", Debug.getPss())
                .put("device_available_memory_bytes", memory.availMem).put("network_rx_bytes", delta(rx0, TrafficStats.getUidRxBytes(Process.myUid())))
                .put("network_tx_bytes", delta(tx0, TrafficStats.getUidTxBytes(Process.myUid()))))
            .put("device", new JSONObject().put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL).put("android_api", Build.VERSION.SDK_INT)
                .put("app_version", appVersion(c))).put("points", samples);
    }

    private static Object delta(long a, long b) { return a < 0 || b < 0 ? JSONObject.NULL : Math.max(0, b-a); }
    private static Object monotonicDelta(long a, long b) { return a <= 0 || b < a ? JSONObject.NULL : b-a; }
    private static int battery(Context c) { return ((BatteryManager)c.getSystemService(Context.BATTERY_SERVICE)).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY); }
    private static String appVersion(Context c) {
        try { return c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName; }
        catch (Exception ignored) { return "unknown"; }
    }
    private static Uri tree(Context c) { String value=c.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString(TREE_URI,null); return value==null?null:Uri.parse(value); }
    private static boolean canReadFolder(Context c, Uri tree) {
        Uri directory = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        try (Cursor cursor = c.getContentResolver().query(directory,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID}, null, null, null)) {
            return cursor != null && cursor.moveToFirst();
        }
    }
    private static void writeFile(Context c, String name, String mime, String text) throws Exception {
        Uri tree=tree(c); if(tree==null)throw new IllegalStateException("folder missing");
        String directoryId = DocumentsContract.getTreeDocumentId(tree);
        Uri dir=DocumentsContract.buildDocumentUriUsingTree(tree, directoryId);
        Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        Uri file = null;
        try (Cursor cursor = c.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME},
            null, null, null)) {
            if (cursor != null) while (cursor.moveToNext()) {
                if (name.equals(cursor.getString(1))) {
                    file = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0));
                    break;
                }
            }
        }
        if (file == null) file=DocumentsContract.createDocument(c.getContentResolver(),dir,mime,name);
        if(file==null)throw new IllegalStateException("create failed");
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        try (ParcelFileDescriptor descriptor = c.getContentResolver().openFileDescriptor(file, "rwt")) {
            if (descriptor == null) throw new IllegalStateException("open failed");
            try (FileOutputStream out = new FileOutputStream(descriptor.getFileDescriptor())) {
                out.write(bytes);
                out.flush();
                descriptor.getFileDescriptor().sync();
            }
        }
        Long observedSize = null;
        try (Cursor cursor = c.getContentResolver().query(file,
            new String[] {DocumentsContract.Document.COLUMN_SIZE}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0))
                observedSize = cursor.getLong(0);
        }
        if (!DriveWriteVerification.matchesSize(bytes.length, observedSize))
            throw new IOException("provider size mismatch");
    }

    private static void writeNewFile(Context c, String name, String mime, String text) throws Exception {
        Uri tree = tree(c); if (tree == null) throw new IllegalStateException("folder missing");
        String directoryId = DocumentsContract.getTreeDocumentId(tree);
        Uri dir = DocumentsContract.buildDocumentUriUsingTree(tree, directoryId);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        try (Cursor cursor = c.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
            if (cursor != null) while (cursor.moveToNext())
                if (name.equals(cursor.getString(0))) return;
        }
        Uri file = DocumentsContract.createDocument(c.getContentResolver(), dir, mime, name);
        if (file == null) throw new IllegalStateException("create failed");
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        try (ParcelFileDescriptor descriptor = c.getContentResolver().openFileDescriptor(file, "rwt")) {
            if (descriptor == null) throw new IllegalStateException("open failed");
            try (FileOutputStream out = new FileOutputStream(descriptor.getFileDescriptor())) {
                out.write(bytes); out.flush(); descriptor.getFileDescriptor().sync();
            }
        }
    }

    static void writeDailyDiagnostics(Context context, String name, String text) throws Exception {
        writeNewFile(context, name, "application/x-ndjson", text);
        pruneDailyDiagnostics(context, 15);
    }

    private static void pruneDailyDiagnostics(Context context, int keep) throws Exception {
        Uri tree = tree(context); if (tree == null) throw new IllegalStateException("folder missing");
        String directoryId = DocumentsContract.getTreeDocumentId(tree);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        List<DiagnosticRetentionPolicy.Entry> entries = new ArrayList<>();
        try (Cursor cursor = context.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
            if (cursor != null) while (cursor.moveToNext()) {
                String name = cursor.getString(1);
                if (DiagnosticRetentionPolicy.isManaged(name))
                    entries.add(new DiagnosticRetentionPolicy.Entry(cursor.getString(0), name));
            }
        }
        for (DiagnosticRetentionPolicy.Entry entry :
            DiagnosticRetentionPolicy.entriesToDelete(entries, keep)) {
            Uri document = DocumentsContract.buildDocumentUriUsingTree(tree, entry.id());
            DocumentsContract.deleteDocument(context.getContentResolver(), document);
        }
    }
}
