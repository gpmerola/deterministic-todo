package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.LinkedHashMap;
import java.util.Map;

final class IntensiveDiagnosticDebugState {
    static final String PREFS = "movement_intensive_status";

    private IntensiveDiagnosticDebugState() {}

    static long prepareExperiment(Context context, String experimentId) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String previous = p.getString("experiment_id", null);
        if (experimentId != null && experimentId.equals(previous))
            return p.getLong("last_window_at", 0);
        p.edit().putString("experiment_id", experimentId == null ? "unknown" : experimentId)
            .remove("coverage_gap_count").remove("last_gap_start_ms")
            .remove("last_gap_end_ms").remove("last_gap_duration_ms")
            .remove("max_gap_duration_ms").remove("last_gap_reason")
            .remove("missing_expected_windows").apply();
        return 0;
    }

    static void gap(Context context, IntensiveGapPolicy.Gap gap, String reason) {
        if (!gap.present()) return;
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        p.edit().putLong("coverage_gap_count", p.getLong("coverage_gap_count", 0) + 1)
            .putLong("last_gap_start_ms", gap.startMillis())
            .putLong("last_gap_end_ms", gap.endMillis())
            .putLong("last_gap_duration_ms", gap.durationMillis())
            .putLong("max_gap_duration_ms", Math.max(p.getLong("max_gap_duration_ms", 0),
                gap.durationMillis()))
            .putString("last_gap_reason", reason)
            .putLong("missing_expected_windows",
                p.getLong("missing_expected_windows", 0) + gap.missingExpectedWindows())
            .apply();
    }

    static Map<String, Object> values(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        LinkedHashMap<String, Object> result = new LinkedHashMap<>();
        result.put("intensive_status", p.getString("status", "unknown"));
        add(result, p, "last_window_at", "intensive_last_window_at_ms");
        add(result, p, "coverage_gap_count", "intensive_coverage_gap_count");
        add(result, p, "last_gap_start_ms", "intensive_last_gap_start_ms");
        add(result, p, "last_gap_end_ms", "intensive_last_gap_end_ms");
        add(result, p, "last_gap_duration_ms", "intensive_last_gap_duration_ms");
        add(result, p, "max_gap_duration_ms", "intensive_max_gap_duration_ms");
        add(result, p, "missing_expected_windows", "intensive_missing_expected_windows");
        result.put("intensive_last_gap_reason", p.getString("last_gap_reason", null));
        return result;
    }

    private static void add(Map<String, Object> result, SharedPreferences p,
                            String preference, String column) {
        result.put(column, p.contains(preference) ? p.getLong(preference, 0) : null);
    }
}
