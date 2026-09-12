package app.deterministic.todo.runtracker;

import java.io.File;

/** Pure naming rules for crash-safe, immutable intensive diagnostic chunks. */
final class IntensiveChunkFilePolicy {
    private IntensiveChunkFilePolicy() {}

    static String completedName(String activeName) {
        if (activeName == null || !activeName.endsWith(".jsonl.active"))
            throw new IllegalArgumentException("invalid_active_chunk_name");
        return activeName.substring(0, activeName.length() - ".active".length());
    }

    static String uniqueActiveName(File directory, String experimentId, String segmentId,
                                   long timestampMillis) {
        String base = "intensive_" + experimentId + "_" + segmentId + "_" + timestampMillis;
        String candidate = base + ".jsonl.active";
        int suffix = 1;
        while (new File(directory, candidate).exists()
            || new File(directory, completedName(candidate)).exists()) {
            candidate = base + "_" + suffix++ + ".jsonl.active";
        }
        return candidate;
    }

    static boolean complete(File active) {
        if (active == null || !active.isFile()) return false;
        String completed;
        try { completed = completedName(active.getName()); }
        catch (IllegalArgumentException invalid) { return false; }
        File target = new File(active.getParentFile(), completed);
        return !target.exists() && active.renameTo(target);
    }
}
