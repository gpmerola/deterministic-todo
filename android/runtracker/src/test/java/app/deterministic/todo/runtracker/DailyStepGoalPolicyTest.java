package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class DailyStepGoalPolicyTest {
    @Test public void goalIsBounded() {
        assertEquals(1_000, DailyStepGoalPolicy.normalize(10));
        assertEquals(12_000, DailyStepGoalPolicy.normalize(12_000));
        assertEquals(100_000, DailyStepGoalPolicy.normalize(999_999));
    }

    @Test public void progressNeverEscapesTheRing() {
        assertEquals(0f, DailyStepGoalPolicy.progress(-1, 10_000), 0.0001f);
        assertEquals(0.5f, DailyStepGoalPolicy.progress(5_000, 10_000), 0.0001f);
        assertEquals(1f, DailyStepGoalPolicy.progress(12_000, 10_000), 0.0001f);
    }
}
