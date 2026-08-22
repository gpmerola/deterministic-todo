package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.LinkedHashMap;
import java.util.Map;

/** Privacy-safe state of the previous diagnostics upload attempt. */
final class DiagnosticUploadDebugState {
    private static final String PREFS = "diagnostic_upload_debug";

    private DiagnosticUploadDebugState() {}

    static void started(Context context, long now, boolean manual) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        p.edit().putBoolean("current_in_progress", true).putLong("current_started_at_ms", now)
            .putBoolean("current_manual", manual)
            .putLong("attempt_count", p.getLong("attempt_count", 0) + 1).apply();
    }

    static void succeeded(Context context, long now) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long started = p.getLong("current_started_at_ms", now);
        p.edit().putBoolean("current_in_progress", false).putString("last_phase", "success")
            .putLong("last_started_at_ms", started).putLong("last_finished_at_ms", now)
            .putLong("last_duration_ms", Math.max(0, now - started)).putLong("last_success_at_ms", now)
            .putLong("consecutive_failures", 0).remove("error_code").apply();
    }

    static void failed(Context context, long now, Throwable error) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long started = p.getLong("current_started_at_ms", now);
        p.edit().putBoolean("current_in_progress", false).putString("last_phase", "error")
            .putLong("last_started_at_ms", started).putLong("last_finished_at_ms", now)
            .putLong("last_duration_ms", Math.max(0, now - started))
            .putLong("consecutive_failures", p.getLong("consecutive_failures", 0) + 1)
            .putString("error_code", errorCode(error)).apply();
    }

    static Map<String, Object> values(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        LinkedHashMap<String, Object> result = new LinkedHashMap<>();
        result.put("current_in_progress", p.getBoolean("current_in_progress", false));
        result.put("current_manual", p.contains("current_manual")
            ? p.getBoolean("current_manual", false) : null);
        addLong(result, p, "current_started_at_ms");
        result.put("last_phase", p.getString("last_phase", "never_run"));
        addLong(result, p, "last_started_at_ms");
        addLong(result, p, "last_finished_at_ms");
        addLong(result, p, "last_duration_ms");
        addLong(result, p, "last_success_at_ms");
        result.put("attempt_count", p.getLong("attempt_count", 0));
        result.put("consecutive_failures", p.getLong("consecutive_failures", 0));
        result.put("error_code", p.getString("error_code", null));
        return result;
    }

    static String errorCode(Throwable error) {
        return error == null ? "Unknown" : error.getClass().getSimpleName();
    }

    private static void addLong(Map<String, Object> result, SharedPreferences p, String key) {
        result.put(key, p.contains(key) ? p.getLong(key, 0) : null);
    }
}
