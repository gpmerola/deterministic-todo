package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public class DiagnosticRetentionPolicyTest {
    @Test public void diagnosticUploadRunsHourlyDuringDebugging() {
        assertEquals(1, DiagnosticDriveWorker.PERIODIC_INTERVAL_HOURS);
    }

    @Test public void acceptsThreeHourlyDiagnosticSnapshots() {
        assertTrue(DiagnosticRetentionPolicy.isManaged(
            "todo_diagnostics_2026-08-21_12.jsonl"));
    }

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
