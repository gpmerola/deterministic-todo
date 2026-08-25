package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.Instant;

/** Seven-day, privacy-safe diagnostic payload written to one of two crash-safe slots. */
final class RollingDiagnosticBundle {
    static final int SCHEMA_VERSION = 1;
    static final int WINDOW_DAYS = 7;
    static final long WINDOW_MILLIS = WINDOW_DAYS * 24L * 60L * 60L * 1000L;
    private static final String PREFS = "rolling_diagnostic_bundle";
    private static final String LAST_SLOT = "last_successful_slot";

    private RollingDiagnosticBundle() {}

    static String nextSlot(Context context) {
        String last = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(LAST_SLOT, "b");
        return "a".equals(last) ? "b" : "a";
    }

    static String fileName(String slot) {
        return "diagnostics_last_7_days_" + slot + ".json";
    }

    static void markSuccessful(Context context, String slot) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(LAST_SLOT, slot).apply();
    }

    static JSONObject create(Context context, long observedAt, boolean manual,
                             String diagnosticJsonl) throws Exception {
        long windowStart = observedAt - WINDOW_MILLIS;
        JSONArray events = new JSONArray();
        int invalidLines = 0;
        for (String line : diagnosticJsonl.split("\\R")) {
            if (line.isBlank()) continue;
            try {
                JSONObject event = new JSONObject(line);
                String timestamp = event.optString("timestamp", "");
                if (timestamp.isEmpty() || Instant.parse(timestamp).toEpochMilli() >= windowStart)
                    events.put(event);
            } catch (Exception invalid) {
                invalidLines++;
            }
        }
        return new JSONObject()
            .put("schema_version", SCHEMA_VERSION)
            .put("kind", "rolling_diagnostic_bundle")
            .put("trigger", manual ? "manual" : "automatic")
            .put("generated_at_ms", observedAt)
            .put("window_start_ms", windowStart)
            .put("window_days", WINDOW_DAYS)
            .put("app_events", events)
            .put("invalid_app_event_lines", invalidLines)
            .put("unified_snapshot", UnifiedDiagnosticReport.create(context, observedAt))
            .put("storage", new JSONObject()
                .put("strategy", "alternating_two_slots")
                .put("automatic_drive_deletion", false))
            .put("privacy", new JSONObject()
                .put("todo_content_recorded", false)
                .put("coordinates_recorded", false)
                .put("auth_key_recorded", false));
    }
}
