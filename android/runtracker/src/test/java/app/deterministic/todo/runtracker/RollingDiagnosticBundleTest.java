package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class RollingDiagnosticBundleTest {
    @Test public void usesTwoStableFilesAndSevenDayWindow() {
        assertEquals(7, RollingDiagnosticBundle.WINDOW_DAYS);
        assertEquals("diagnostics_last_7_days_a.json",
            RollingDiagnosticBundle.fileName("a"));
        assertEquals("diagnostics_last_7_days_b.json",
            RollingDiagnosticBundle.fileName("b"));
        assertEquals(DriveFolderLayout.APP_DIAGNOSTICS,
            DriveFolderLayout.folderFor(RollingDiagnosticBundle.fileName("a")));
    }

    @Test public void fallbackSnapshotIsAlwaysSerializable() throws Exception {
        org.json.JSONObject fallback = UnifiedDiagnosticReport.fallback(1234L,
            java.time.ZoneId.of("Europe/Rome"), "RoomFailure");
        assertEquals("generation_fallback", fallback.getString("report_status"));
        assertEquals("RoomFailure", fallback.getString("generation_error_code"));
    }
}
