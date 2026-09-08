package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BipUSampleMergePolicyTest {
    @Test public void replacesPartialMinuteWhenStepsIncrease() {
        assertTrue(BipUSampleMergePolicy.shouldReplace(4, 11));
    }

    @Test public void ignoresExactDuplicate() {
        assertFalse(BipUSampleMergePolicy.shouldReplace(11, 11));
    }

    @Test public void ignoresRegressiveSample() {
        assertFalse(BipUSampleMergePolicy.shouldReplace(11, 4));
    }
}
