package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public class ManualDiagnosticExportSchedulerTest {
    @Test public void manualAndAutomaticUseTheSameDiagnosticWorkerIdentity() {
        assertEquals("movement-manual-diagnostic-export",
            ManualDiagnosticExportScheduler.DIAGNOSTIC_WORK);
    }

    @Test public void driveWritesAreSerializedAcrossIndependentWorkers() throws Exception {
        Method method = DriveTestExportManager.class.getDeclaredMethod(
            "writeNewFile", android.content.Context.class, String.class,
            String.class, String.class);
        assertEquals(true, Modifier.isSynchronized(method.getModifiers()));
    }

    @Test public void rollingSlotOverwriteIsSerialized() throws Exception {
        Method method = DriveTestExportManager.class.getDeclaredMethod(
            "writeFile", android.content.Context.class, String.class,
            String.class, String.class);
        assertEquals(true, Modifier.isSynchronized(method.getModifiers()));
    }
}
