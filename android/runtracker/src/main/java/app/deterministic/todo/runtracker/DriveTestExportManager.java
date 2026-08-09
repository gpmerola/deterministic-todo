package app.deterministic.todo.runtracker;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.net.TrafficStats;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Debug;
import android.os.Process;
import android.provider.DocumentsContract;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

final class DriveTestExportManager {
    private static final String PREFS = "movement_drive_export";
    private static final String TREE_URI = "tree_uri";
    private DriveTestExportManager() {}

    static void setFolder(Context context, Uri uri) {
        context.getContentResolver().takePersistableUriPermission(uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(TREE_URI, uri.toString()).apply();
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

    static void finish(Context context, RunSession session, List<TrackPoint> points) {
        if (!isConfigured(context)) return;
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { new Thread(() -> write(context, session, points, m.steps), "movement-drive-export").start(); }
            public void onPermissionRequired() { fallback(); } public void onUnavailable() { fallback(); } public void onError() { fallback(); }
            private void fallback() { new Thread(() -> write(context, session, points, null), "movement-drive-export").start(); }
        });
    }

    private static void write(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd) {
        try {
            String base = String.format(java.util.Locale.ROOT, "%d_%s_session-%06d", s.startedAtMillis, s.activityType, s.id);
            writeFile(c, base + ".gpx", "application/gpx+xml", GpxExporter.export(s, points));
            writeFile(c, base + "_diagnostics.json", "application/json", diagnostics(c, s, points, stepsEnd).toString(2));
        } catch (Exception ignored) {}
    }

    private static JSONObject diagnostics(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd) throws Exception {
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
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo(); ((ActivityManager)c.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
        return new JSONObject().put("schema_version", 1).put("session_id", s.id).put("activity", s.activityType)
            .put("started_at_ms", s.startedAtMillis).put("ended_at_ms", s.endedAtMillis).put("duration_ms", s.endedAtMillis - s.startedAtMillis)
            .put("distance_m", s.distanceMeters).put("steps_start_daily", steps0 < 0 ? JSONObject.NULL : steps0)
            .put("steps_end_daily", stepsEnd == null ? JSONObject.NULL : stepsEnd).put("steps_delta", stepsEnd == null || steps0 < 0 ? JSONObject.NULL : stepsEnd - steps0)
            .put("gps", new JSONObject().put("samples", points.size()).put("accepted", accepted).put("rejected", points.size()-accepted)
                .put("rejection_reasons", reasons).put("accuracy_mean_m", points.isEmpty()?JSONObject.NULL:accuracySum/points.size()).put("accuracy_max_m", accuracyMax))
            .put("resources", new JSONObject().put("battery_start_pct", p.getInt(s.id + ".battery", -1)).put("battery_end_pct", battery(c))
                .put("wall_elapsed_ms", elapsed0 == 0 ? JSONObject.NULL : android.os.SystemClock.elapsedRealtime()-elapsed0)
                .put("process_cpu_ms", cpu0 == 0 ? JSONObject.NULL : Process.getElapsedCpuTime()-cpu0).put("process_pss_kb", Debug.getPss())
                .put("device_available_memory_bytes", memory.availMem).put("network_rx_bytes", delta(rx0, TrafficStats.getUidRxBytes(Process.myUid())))
                .put("network_tx_bytes", delta(tx0, TrafficStats.getUidTxBytes(Process.myUid()))))
            .put("device", new JSONObject().put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL).put("android_api", Build.VERSION.SDK_INT)
                .put("app_version", appVersion(c))).put("points", samples);
    }

    private static Object delta(long a, long b) { return a < 0 || b < 0 ? JSONObject.NULL : Math.max(0, b-a); }
    private static int battery(Context c) { return ((BatteryManager)c.getSystemService(Context.BATTERY_SERVICE)).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY); }
    private static String appVersion(Context c) {
        try { return c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName; }
        catch (Exception ignored) { return "unknown"; }
    }
    private static Uri tree(Context c) { String value=c.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString(TREE_URI,null); return value==null?null:Uri.parse(value); }
    private static void writeFile(Context c, String name, String mime, String text) throws Exception {
        Uri tree=tree(c); if(tree==null)return; Uri dir=DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        Uri file=DocumentsContract.createDocument(c.getContentResolver(),dir,mime,name); if(file==null)throw new IllegalStateException("create failed");
        try(OutputStream out=c.getContentResolver().openOutputStream(file,"w")){ if(out==null)throw new IllegalStateException("open failed"); out.write(text.getBytes(StandardCharsets.UTF_8)); }
    }
}
