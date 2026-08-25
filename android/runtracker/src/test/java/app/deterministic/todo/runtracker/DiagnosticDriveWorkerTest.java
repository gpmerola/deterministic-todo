package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import java.time.LocalDateTime;
import org.junit.Test;

public class DiagnosticDriveWorkerTest {
    @Test public void manualRetryKeepsOriginalFileBucket() {
        assertEquals("2026-08-25_15-00-00", DiagnosticDriveWorker.exportBucket(true,
            "2026-08-25_15-00-00", LocalDateTime.of(2026, 8, 25, 15, 9)));
    }

    @Test public void periodicExportUsesCurrentHour() {
        assertEquals("2026-08-25_15", DiagnosticDriveWorker.exportBucket(false, null,
            LocalDateTime.of(2026, 8, 25, 15, 9)));
    }
}
