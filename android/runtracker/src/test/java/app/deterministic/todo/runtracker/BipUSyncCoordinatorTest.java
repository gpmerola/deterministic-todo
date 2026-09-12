package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import org.junit.Test;

public final class BipUSyncCoordinatorTest {
    @Test public void preventsOverlappingManualAndAutomaticImports() {
        BipUSyncCoordinator.release();
        assertTrue(BipUSyncCoordinator.tryAcquire());
        assertFalse(BipUSyncCoordinator.tryAcquire());
        BipUSyncCoordinator.release();
        assertTrue(BipUSyncCoordinator.tryAcquire());
        BipUSyncCoordinator.release();
    }
}
