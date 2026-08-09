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
import android.os.Process;
import android.provider.DocumentsContract;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

final class DriveTestExportManager {
    private static final String PREFS = "movement_drive_export";
    private static final String TREE_URI = "tree_uri";
    private static final String LAST_STATUS = "last_status";
    private static final String LAST_ERROR = "last_error";
    private static final String LAST_EXPORTED_AT = "last_exported_at";
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
        e.apply();
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(id + ".steps", m.steps).apply(); }
            public void onPermissionRequired() {} public void onUnavailable() {} public void onError() {}
        });
    }

    static String status(Context context) {
        android.content.SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String status = p.getString(LAST_STATUS, isConfigured(context) ? "ready" : "not_configured");
        if ("success".equals(status)) return "Ultimo export Drive completato · GPX + JSON";
        if ("exporting".equals(status)) return "Export Drive in corso…";
        if ("failed".equals(status)) return "Ultimo export Drive non riuscito · " + p.getString(LAST_ERROR, "errore_sconosciuto");
        if ("ready".equals(status)) return "Cartella Drive pronta · nessun export completato";
        return "Cartella Drive non collegata";
    }

    static void finish(Context context, RunSession session, List<TrackPoint> points, Completion completion) {
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
        long exportedAt = System.currentTimeMillis();
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo(); ((ActivityManager)c.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
        return new JSONObject().put("schema_version", 1).put("session_id", s.id).put("activity", s.activityType)
            .put("started_at_ms", s.startedAtMillis).put("ended_at_ms", s.endedAtMillis).put("duration_ms", s.endedAtMillis - s.startedAtMillis)
            .put("exported_at_ms", exportedAt)
            .put("distance_m", s.distanceMeters).put("steps_start_daily", steps0 < 0 ? JSONObject.NULL : steps0)
            .put("steps_end_daily", stepsEnd == null ? JSONObject.NULL : stepsEnd)
            .put("steps_end_observed_at_ms", stepsEnd == null ? JSONObject.NULL : exportedAt)
            .put("steps_delta", stepsEnd == null || steps0 < 0 || stepsEnd < steps0 ? JSONObject.NULL : stepsEnd - steps0)
            .put("steps_end_status", healthStatus)
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
        try(OutputStream out=c.getContentResolver().openOutputStream(file,"w")){ if(out==null)throw new IllegalStateException("open failed"); out.write(text.getBytes(StandardCharsets.UTF_8)); }
    }
}
