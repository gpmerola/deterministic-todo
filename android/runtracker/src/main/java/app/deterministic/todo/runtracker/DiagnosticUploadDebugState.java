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
            .putString("current_phase", "prepare")
            .putLong("attempt_count", p.getLong("attempt_count", 0) + 1).apply();
    }

    static void phaseStarted(Context context, String phase, long now) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("current_phase", phase)
            .putLong("phase_" + phase + "_started_at_ms", now).apply();
    }

    static void phaseFinished(Context context, String phase, long now, Throwable error,
                              boolean required) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long started = p.getLong("phase_" + phase + "_started_at_ms", now);
        SharedPreferences.Editor e = p.edit()
            .putLong("phase_" + phase + "_finished_at_ms", now)
            .putLong("phase_" + phase + "_duration_ms", Math.max(0, now - started))
            .putString("phase_" + phase + "_outcome", error == null ? "success" : "error")
            .putBoolean("phase_" + phase + "_required", required);
        if (error == null) e.remove("phase_" + phase + "_error_code");
        else e.putString("phase_" + phase + "_error_code", errorCode(error));
        e.apply();
    }

    static void threeWaySummary(Context context, int attempted, int succeeded,
                                String firstFailureCode) {
        SharedPreferences.Editor e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putInt("three_way_attempted", attempted)
            .putInt("three_way_succeeded", succeeded)
            .putInt("three_way_failed", Math.max(0, attempted - succeeded));
        if (firstFailureCode == null) e.remove("three_way_first_failure_code");
        else e.putString("three_way_first_failure_code", firstFailureCode);
        e.apply();
    }

    static void succeeded(Context context, long now) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long started = p.getLong("current_started_at_ms", now);
        p.edit().putBoolean("current_in_progress", false).putString("last_phase", "success")
            .remove("current_phase")
            .putLong("last_started_at_ms", started).putLong("last_finished_at_ms", now)
            .putLong("last_duration_ms", Math.max(0, now - started)).putLong("last_success_at_ms", now)
            .putLong("consecutive_failures", 0).remove("error_code").apply();
    }

    static void failed(Context context, long now, Throwable error) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long started = p.getLong("current_started_at_ms", now);
        p.edit().putBoolean("current_in_progress", false).putString("last_phase", "error")
            .remove("current_phase")
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
        result.put("current_phase", p.getString("current_phase", null));
        result.put("last_phase", p.getString("last_phase", "never_run"));
        addLong(result, p, "last_started_at_ms");
        addLong(result, p, "last_finished_at_ms");
        addLong(result, p, "last_duration_ms");
        addLong(result, p, "last_success_at_ms");
        result.put("attempt_count", p.getLong("attempt_count", 0));
        result.put("consecutive_failures", p.getLong("consecutive_failures", 0));
        result.put("error_code", p.getString("error_code", null));
        LinkedHashMap<String, Object> phases = new LinkedHashMap<>();
        for (String phase : new String[] {"read_local_log", "raw_log_upload",
            "unified_generate", "unified_upload", "three_way_refresh"}) {
            LinkedHashMap<String, Object> value = new LinkedHashMap<>();
            value.put("outcome", p.getString("phase_" + phase + "_outcome", "never_run"));
            value.put("required", p.contains("phase_" + phase + "_required")
                ? p.getBoolean("phase_" + phase + "_required", false) : null);
            addLong(value, p, "phase_" + phase + "_started_at_ms");
            addLong(value, p, "phase_" + phase + "_finished_at_ms");
            addLong(value, p, "phase_" + phase + "_duration_ms");
            value.put("error_code", p.getString("phase_" + phase + "_error_code", null));
            phases.put(phase, value);
        }
        result.put("phases", phases);
        LinkedHashMap<String, Object> refresh = new LinkedHashMap<>();
        refresh.put("attempted", p.contains("three_way_attempted")
            ? p.getInt("three_way_attempted", 0) : null);
        refresh.put("succeeded", p.contains("three_way_succeeded")
            ? p.getInt("three_way_succeeded", 0) : null);
        refresh.put("failed", p.contains("three_way_failed")
            ? p.getInt("three_way_failed", 0) : null);
        refresh.put("first_failure_code",
            p.getString("three_way_first_failure_code", null));
        result.put("three_way_refresh_summary", refresh);
        return result;
    }

    static String errorCode(Throwable error) {
        return error == null ? "Unknown" : error.getClass().getSimpleName();
    }

    private static void addLong(Map<String, Object> result, SharedPreferences p, String key) {
        result.put(key, p.contains(key) ? p.getLong(key, 0) : null);
    }
}
