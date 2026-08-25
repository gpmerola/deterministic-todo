package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class ManualDiagnosticExportSchedulerTest {
    @Test public void passiveAndDiagnosticBranchesHaveIndependentWorkIdentities() {
        assertNotEquals(ManualDiagnosticExportScheduler.MOVEMENT_WORK,
            ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK);
        assertNotEquals(ManualDiagnosticExportScheduler.MOVEMENT_WORK,
            ManualDiagnosticExportScheduler.INTENSIVE_WORK);
        assertNotEquals(ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK,
            ManualDiagnosticExportScheduler.INTENSIVE_WORK);
        assertEquals(2, ManualDiagnosticExportScheduler.INTENSIVE_DELAY_MINUTES);
    }
}
