package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

final class DiagnosticRetentionPolicy {
    static final String PREFIX = "todo_diagnostics_";
    static final String SUFFIX = ".jsonl";

    record Entry(String id, String name) {}

    private DiagnosticRetentionPolicy() {}

    static boolean isManaged(String name) {
        return name != null && name.startsWith(PREFIX) && name.endsWith(SUFFIX);
    }

    static List<Entry> entriesToDelete(List<Entry> entries, int keep) {
        List<Entry> managed = new ArrayList<>();
        for (Entry entry : entries) if (isManaged(entry.name())) managed.add(entry);
        managed.sort(Comparator.comparing(Entry::name).reversed());
        if (managed.size() <= keep) return List.of();
        return new ArrayList<>(managed.subList(Math.max(0, keep), managed.size()));
    }
}
