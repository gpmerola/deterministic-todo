package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public class DiagnosticDriveWorkerTest {
    @Test public void periodicExportIntervalIsThreeHours() {
        assertEquals(3L, DiagnosticDriveWorker.PERIODIC_INTERVAL_HOURS);
    }
}
