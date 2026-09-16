package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import androidx.work.ListenableWorker;
import org.junit.Test;

public class DiagnosticDriveWorkerTest {
    @Test public void periodicExportIntervalIsThreeHours() {
        assertEquals(3L, DiagnosticDriveWorker.PERIODIC_INTERVAL_HOURS);
    }

    @Test public void automaticTransientFailureDoesNotEnterWorkManagerBackoff() {
        ListenableWorker.Result result = DiagnosticDriveWorker.workResult(
            DiagnosticDriveWorker.ExportOutcome.RETRY, false);
        assertEquals(ListenableWorker.Result.success().getClass(), result.getClass());
    }

    @Test public void manualFallbackTransientFailureStillRetries() {
        ListenableWorker.Result result = DiagnosticDriveWorker.workResult(
            DiagnosticDriveWorker.ExportOutcome.RETRY, true);
        assertEquals(ListenableWorker.Result.retry().getClass(), result.getClass());
    }
}
