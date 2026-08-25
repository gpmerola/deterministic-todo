package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertNotEquals;

import org.junit.Test;

public class ManualDiagnosticExportSchedulerTest {
    @Test public void passiveAndDiagnosticBranchesHaveIndependentWorkIdentities() {
        assertNotEquals(ManualDiagnosticExportScheduler.MOVEMENT_WORK,
            ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK);
    }
}
