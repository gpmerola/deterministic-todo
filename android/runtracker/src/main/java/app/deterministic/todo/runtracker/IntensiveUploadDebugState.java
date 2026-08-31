package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.LinkedHashMap;
import java.util.Map;

/** Privacy-safe observation of the bounded intensive backlog uploader. */
final class IntensiveUploadDebugState {
    private static final String PREFS = "movement_intensive_upload_debug";

    private IntensiveUploadDebugState() {}

    static void finished(Context context, long startedAt, int pendingBefore,
                         int attempted, int succeeded, int pendingAfter,
                         String firstFailureCode) {
        long now = System.currentTimeMillis();
        SharedPreferences.Editor editor = context.getSharedPreferences(PREFS,
            Context.MODE_PRIVATE).edit()
            .putLong("last_started_at_ms", startedAt)
            .putLong("last_finished_at_ms", now)
            .putLong("last_duration_ms", Math.max(0, now - startedAt))
            .putInt("pending_before", pendingBefore)
            .putInt("attempted", attempted)
            .putInt("succeeded", succeeded)
            .putInt("pending_after", pendingAfter)
            .putString("outcome", firstFailureCode == null ? "success" : "partial_or_failed");
        if (firstFailureCode == null) editor.remove("first_failure_code");
        else editor.putString("first_failure_code", firstFailureCode);
        editor.apply();
    }

    static Map<String, Object> values(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        LinkedHashMap<String, Object> result = new LinkedHashMap<>();
        result.put("outcome", p.getString("outcome", "never_run"));
        addLong(result, p, "last_started_at_ms");
        addLong(result, p, "last_finished_at_ms");
        addLong(result, p, "last_duration_ms");
        addInt(result, p, "pending_before");
        addInt(result, p, "attempted");
        addInt(result, p, "succeeded");
        addInt(result, p, "pending_after");
        result.put("first_failure_code", p.getString("first_failure_code", null));
        result.put("maximum_chunks_per_cycle", IntensiveChunkUploader.MAXIMUM_PER_CYCLE);
        return result;
    }

    private static void addLong(Map<String, Object> result, SharedPreferences p, String key) {
        result.put(key, p.contains(key) ? p.getLong(key, 0) : null);
    }

    private static void addInt(Map<String, Object> result, SharedPreferences p, String key) {
        result.put(key, p.contains(key) ? p.getInt(key, 0) : null);
    }
}
