package app.deterministic.todo.deterministic_todo;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** DUMP-protected, content-free summary of the Flutter Todo sync journal. */
public final class TodoSyncDebugProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        if (getContext() == null || !"status".equals(uri.getLastPathSegment())) {
            throw new IllegalArgumentException("Supported path: /status");
        }
        Map<String, Object> values = readStatus();
        String[] columns = projection == null
            ? values.keySet().toArray(new String[0]) : projection;
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        Object[] row = new Object[columns.length];
        for (int i = 0; i < columns.length; i++) {
            if (!values.containsKey(columns[i])) {
                throw new IllegalArgumentException("Unknown column: " + columns[i]);
            }
            row[i] = values.get(columns[i]);
        }
        cursor.addRow(row);
        return cursor;
    }

    private Map<String, Object> readStatus() {
        JSONObject lastCompleted = null;
        JSONObject lastFailed = null;
        JSONObject lastRecovered = null;
        JSONObject lastRealtimeProblem = null;
        List<File> files = new ArrayList<>();
        collectDiagnosticFiles(getContext().getFilesDir(), files);
        File dataRoot = getContext().getFilesDir().getParentFile();
        if (dataRoot != null) {
            collectDiagnosticFiles(new File(dataRoot, "app_flutter"), files);
        }
        files.sort(Comparator.comparingLong(File::lastModified));
        for (File file : files) {
            try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    JSONObject event = new JSONObject(line);
                    String name = event.optString("event");
                    if ("sync_completed".equals(name)) lastCompleted = newer(lastCompleted, event);
                    if ("sync_failed".equals(name)) lastFailed = newer(lastFailed, event);
                    if ("sync_recovered".equals(name)) lastRecovered = newer(lastRecovered, event);
                    if ("realtime_status".equals(name)
                        && !"subscribed".equals(event.optString("status"))) {
                        lastRealtimeProblem = newer(lastRealtimeProblem, event);
                    }
                }
            } catch (Exception ignored) {
                // A partially rotated line must not make the shell status unavailable.
            }
        }

        LinkedHashMap<String, Object> values = new LinkedHashMap<>();
        values.put("state", syncState(lastCompleted, lastFailed, lastRecovered));
        put(values, "last_success_at", lastCompleted, "timestamp");
        put(values, "last_success_cycle", lastCompleted, "cycle_id");
        put(values, "last_failure_at", lastFailed, "timestamp");
        put(values, "last_failure_cycle", lastFailed, "cycle_id");
        put(values, "last_failure_stage", lastFailed, "sync_stage");
        put(values, "last_error_class", lastFailed, "error_class");
        put(values, "last_error_type", lastFailed, "error_type");
        put(values, "last_error_code", lastFailed, "error_code");
        put(values, "last_network_state", lastFailed, "network_state");
        put(values, "last_auth_state", lastFailed, "auth_state");
        put(values, "last_pending", lastFailed, "pending");
        put(values, "last_retry_at", lastFailed, "retry_at");
        put(values, "last_recovered_at", lastRecovered, "timestamp");
        put(values, "last_recovered_failures", lastRecovered, "recovered_failures");
        put(values, "last_realtime_problem_at", lastRealtimeProblem, "timestamp");
        put(values, "last_realtime_status", lastRealtimeProblem, "status");
        return values;
    }

    private void collectDiagnosticFiles(File directory, List<File> target) {
        File[] children = directory.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (child.isDirectory()) {
                collectDiagnosticFiles(child, target);
            } else if (child.getName().startsWith("diagnostics")
                && child.getName().contains(".jsonl")) {
                target.add(child);
            }
        }
    }

    private static JSONObject newer(JSONObject current, JSONObject candidate) {
        if (current == null) return candidate;
        return candidate.optString("timestamp").compareTo(current.optString("timestamp")) > 0
            ? candidate : current;
    }

    private static String syncState(JSONObject success, JSONObject failure,
                                    JSONObject recovery) {
        if (failure == null) return success == null ? "unknown" : "healthy";
        String failedAt = failure.optString("timestamp");
        if (recovery != null && recovery.optString("timestamp").compareTo(failedAt) > 0) {
            return "recovered";
        }
        if (success != null && success.optString("timestamp").compareTo(failedAt) > 0) {
            return "healthy";
        }
        return "error";
    }

    private static void put(Map<String, Object> values, String column,
                            JSONObject event, String field) {
        Object value = event == null ? null : event.opt(field);
        values.put(column, value == JSONObject.NULL ? null : value);
    }

    @Override public String getType(Uri uri) {
        return "vnd.android.cursor.item/vnd.deterministic.todo.sync-status";
    }
    @Override public Uri insert(Uri uri, ContentValues values) { throw readOnly(); }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw readOnly();
    }
    @Override public int update(Uri uri, ContentValues values, String selection,
                                String[] selectionArgs) { throw readOnly(); }
    private UnsupportedOperationException readOnly() {
        return new UnsupportedOperationException("Todo sync diagnostics are read-only");
    }
}
