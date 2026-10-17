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

    @Test public void neverDeletesWhatTheStepCounterReads() {
        for (String kept : MovementArchiveCleanup.KEPT_PREFERENCES) {
            assertFalse(kept, MovementArchiveCleanup.ARCHIVED_PREFERENCES.contains(kept));
            assertFalse(kept, kept.startsWith(MovementArchiveCleanup.ARCHIVED_PREFERENCE_PREFIX));
        }
        assertEquals("daily_step_goal", MovementArchiveCleanup.STEP_GOAL);
    }
}
