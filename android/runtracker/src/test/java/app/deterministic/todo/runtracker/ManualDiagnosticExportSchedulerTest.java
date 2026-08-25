package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public class ManualDiagnosticExportSchedulerTest {
    @Test public void passiveAndDiagnosticBranchesHaveIndependentWorkIdentities() {
        assertNotEquals(ManualDiagnosticExportScheduler.MOVEMENT_WORK,
            ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK);
        assertNotEquals(ManualDiagnosticExportScheduler.MOVEMENT_WORK,
            ManualDiagnosticExportScheduler.INTENSIVE_WORK);
        assertNotEquals(ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK,
            ManualDiagnosticExportScheduler.INTENSIVE_WORK);
        assertEquals(2, ManualDiagnosticExportScheduler.INTENSIVE_DELAY_MINUTES);
        assertEquals(1, ManualDiagnosticExportScheduler.DIAGNOSTIC_FALLBACK_DELAY_MINUTES);
    }

    @Test public void driveWritesAreSerializedAcrossIndependentWorkers() throws Exception {
        Method method = DriveTestExportManager.class.getDeclaredMethod(
            "writeNewFile", android.content.Context.class, String.class,
            String.class, String.class);
        assertEquals(true, Modifier.isSynchronized(method.getModifiers()));
    }
}
