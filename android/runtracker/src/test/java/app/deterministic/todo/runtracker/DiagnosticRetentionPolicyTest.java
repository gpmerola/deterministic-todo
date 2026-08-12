package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public class DiagnosticRetentionPolicyTest {
    @Test public void keepsNewestFifteenAndIgnoresOtherFiles() {
        List<DiagnosticRetentionPolicy.Entry> entries = new ArrayList<>();
        for (int day = 1; day <= 17; day++) {
            entries.add(new DiagnosticRetentionPolicy.Entry("id-" + day,
                String.format("todo_diagnostics_2026-08-%02d.jsonl", day)));
        }
        entries.add(new DiagnosticRetentionPolicy.Entry("gpx", "walk.gpx"));
        List<DiagnosticRetentionPolicy.Entry> deleted =
            DiagnosticRetentionPolicy.entriesToDelete(entries, 15);
        assertEquals(List.of("todo_diagnostics_2026-08-02.jsonl",
            "todo_diagnostics_2026-08-01.jsonl"),
            deleted.stream().map(DiagnosticRetentionPolicy.Entry::name).toList());
    }
}
