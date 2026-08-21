package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.LinkedHashMap;
import java.util.Map;

/** Persistent, privacy-safe observability for the most recent explicit Bip U history import. */
final class BipUSyncDebugState {
    private static final String PREFS = "bip_u_sync_debug";

    private BipUSyncDebugState() {}

    static void started(Context context, long startedAtMillis) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", "running").putString("outcome", "running")
            .putLong("started_at_ms", startedAtMillis).remove("finished_at_ms")
            .remove("drive_result").apply();
    }

    static void localFinished(Context context, String outcome, long samples, long inserted,
                              long steps, long heartRateSamples, int requestedHours) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", "drive_pending").putString("outcome", safe(outcome))
            .putLong("finished_at_ms", System.currentTimeMillis())
            .putLong("sample_count", samples).putLong("inserted_count", inserted)
            .putLong("reported_steps", steps).putLong("heart_rate_sample_count", heartRateSamples)
            .putInt("requested_window_hours", requestedHours).apply();
    }

    static void driveFinished(Context context, DriveTestExportManager.ExportResult result) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", result.success() ? "success" : "drive_error")
            .putString("drive_result", safe(result.code()))
            .putLong("drive_finished_at_ms", System.currentTimeMillis()).apply();
    }

    static Map<String, Object> values(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        LinkedHashMap<String, Object> result = new LinkedHashMap<>();
        result.put("bip_sync_phase", p.getString("phase", "never_run"));
        result.put("bip_sync_outcome", p.getString("outcome", "none"));
        addLong(result, p, "started_at_ms", "bip_sync_started_at_ms");
        addLong(result, p, "finished_at_ms", "bip_sync_finished_at_ms");
        addLong(result, p, "drive_finished_at_ms", "bip_sync_drive_finished_at_ms");
        addLong(result, p, "sample_count", "bip_sync_sample_count");
        addLong(result, p, "inserted_count", "bip_sync_inserted_count");
        addLong(result, p, "reported_steps", "bip_sync_reported_steps");
        addLong(result, p, "heart_rate_sample_count", "bip_sync_heart_rate_samples");
        result.put("bip_sync_requested_window_hours", p.contains("requested_window_hours")
            ? p.getInt("requested_window_hours", 0) : null);
        result.put("bip_sync_drive_result", p.getString("drive_result", null));
        return result;
    }

    private static void addLong(Map<String, Object> result, SharedPreferences p,
                                String preference, String column) {
        result.put(column, p.contains(preference) ? p.getLong(preference, 0) : null);
    }

    private static String safe(String value) {
        return value == null || value.isBlank() ? "unknown" : value;
    }
}
