package app.deterministic.todo.runtracker;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class MovementArchiveCleanupTest {
    @Test public void neverCancelsTheStepImport() {
        assertFalse(MovementArchiveCleanup.ARCHIVED_WORKERS.contains(
            LocalStepRecordingWorker.class.getName()));
    }

    @Test public void tagsAreFullyQualifiedRuntrackerClassNames() {
        String prefix = LocalStepRecordingWorker.class.getPackage().getName() + ".";
        for (String tag : MovementArchiveCleanup.ARCHIVED_WORKERS)
            assertTrue(tag, tag.startsWith(prefix) && tag.endsWith("Worker"));
        assertEquals(5, MovementArchiveCleanup.ARCHIVED_WORKERS.size());
    }
}
