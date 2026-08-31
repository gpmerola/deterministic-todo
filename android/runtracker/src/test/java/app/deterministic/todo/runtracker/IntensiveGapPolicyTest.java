package app.deterministic.todo.runtracker;

import org.junit.Test;

import static org.junit.Assert.*;

public final class IntensiveGapPolicyTest {
    @Test public void ignoresNormalSchedulingJitter() {
        assertFalse(IntensiveGapPolicy.between(10_000, 24_999).present());
    }

    @Test public void reportsRestartGapAndExpectedWindows() {
        IntensiveGapPolicy.Gap gap = IntensiveGapPolicy.between(10_000, 40_001);
        assertTrue(gap.present());
        assertEquals(30_001, gap.durationMillis());
        assertEquals(5, gap.missingExpectedWindows());
    }

    @Test public void hasNoGapWithoutPreviousEvidence() {
        assertFalse(IntensiveGapPolicy.between(0, 50_000).present());
    }
}
