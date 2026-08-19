package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.pm.PackageInfo;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Append-only, bounded-window diagnostic chunks. Coordinates and Android record IDs are forbidden. */
final class IntensiveDiagnosticStore {
    private static final String DIRECTORY = "movement_intensive";
    private static final String PREFS = "movement_intensive_store";
    private static final String ACTIVE_FILE = "active_file";
    private static final String SEGMENT_ID = "segment_id";

    private IntensiveDiagnosticStore() {}

    static synchronized String beginSegment(Context context,
                                            IntensiveDiagnosticExperiment.State experiment,
                                            String segmentId,
                                            JSONObject capabilities) throws Exception {
        finishActive(context);
        String name = "intensive_" + experiment.id() + "_" + segmentId + "_"
            + System.currentTimeMillis() + ".jsonl.active";
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(ACTIVE_FILE, name).putString(SEGMENT_ID, segmentId).apply();
        append(context, new JSONObject().put("schema_version", 1).put("kind", "segment_start")
            .put("experiment_id", experiment.id()).put("segment_id", segmentId)
            .put("experiment_started_at_ms", experiment.startedAtMillis())
            .put("experiment_end_at_ms", experiment.endAtMillis())
            .put("observed_at_ms", System.currentTimeMillis())
            .put("app", appVersion(context)).put("capabilities", capabilities)
            .put("window_ms", 5_000).put("privacy", new JSONObject()
                .put("coordinates_recorded", false)
                .put("health_record_ids_recorded", false)
                .put("todo_content_recorded", false)));
        return name;
    }

    static synchronized void append(Context context, JSONObject event) throws Exception {
        String name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_FILE, null);
        if (name == null) throw new IllegalStateException("intensive_segment_missing");
        File file = new File(directory(context), name);
        byte[] bytes = (event.toString() + "\n").getBytes(StandardCharsets.UTF_8);
        try (FileOutputStream output = new FileOutputStream(file, true)) {
            output.write(bytes);
            output.flush();
            output.getFD().sync();
        }
    }

    static synchronized void checkpoint(Context context) {
        finishActive(context);
        IntensiveDiagnosticExperiment.State experiment = IntensiveDiagnosticExperiment.state(context);
        String segmentId = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SEGMENT_ID, null);
        if (!experiment.active(System.currentTimeMillis()) || segmentId == null) return;
        try {
            String name = "intensive_" + experiment.id() + "_" + segmentId + "_"
                + System.currentTimeMillis() + ".jsonl.active";
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(ACTIVE_FILE, name).apply();
            append(context, new JSONObject().put("schema_version", 1)
                .put("kind", "segment_continuation").put("experiment_id", experiment.id())
                .put("segment_id", segmentId).put("observed_at_ms", System.currentTimeMillis())
                .put("app", appVersion(context)));
        } catch (Exception ignored) {}
    }

    private static void finishActive(Context context) {
        String name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_FILE, null);
        if (name == null) return;
        File active = new File(directory(context), name);
        if (active.exists()) {
            String completedName = name.endsWith(".active")
                ? name.substring(0, name.length() - ".active".length()) : name + ".jsonl";
            active.renameTo(new File(directory(context), completedName));
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(ACTIVE_FILE).apply();
    }

    static synchronized List<File> pendingChunks(Context context) {
        File[] files = directory(context).listFiles((dir, name) -> name.endsWith(".jsonl"));
        List<File> result = new ArrayList<>();
        if (files != null) java.util.Collections.addAll(result, files);
        result.sort(Comparator.comparing(File::getName));
        return result;
    }

    static synchronized void uploaded(File file) {
        if (file != null && file.isFile()) file.delete();
    }

    private static File directory(Context context) {
        File directory = new File(context.getFilesDir(), DIRECTORY);
        if (!directory.exists() && !directory.mkdirs())
            throw new IllegalStateException("intensive_directory_failed");
        return directory;
    }

    private static JSONObject appVersion(Context context) throws Exception {
        PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
        return new JSONObject().put("version_name", info.versionName)
            .put("version_code", info.getLongVersionCode())
            .put("android_api", android.os.Build.VERSION.SDK_INT)
            .put("algorithm_version", "cadence-observation-v1");
    }
}
