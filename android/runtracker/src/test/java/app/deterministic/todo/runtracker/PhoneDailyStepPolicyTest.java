package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class PhoneDailyStepPolicyTest {
    @Test public void sameDayAddsMonotonicDelta() {
        PhoneDailyStepPolicy.Update value = PhoneDailyStepPolicy.update(
            20, 150, 140, true, true, false, false);
        assertEquals(30, value.steps());
        assertEquals(10, value.delta());
    }

    @Test public void newDayUsesFirstReadingOnlyAsBaseline() {
        PhoneDailyStepPolicy.Update value = PhoneDailyStepPolicy.update(
            0, 5_000, 2_300, true, false, false, false);
        assertEquals(0, value.steps());
        assertEquals(0, value.delta());
    }

    @Test public void migrationClearsAlreadyContaminatedCurrentDay() {
        PhoneDailyStepPolicy.Update value = PhoneDailyStepPolicy.update(
            2_705, 5_000, 5_000, true, true, false, true);
        assertEquals(0, value.steps());
        assertEquals(0, value.delta());
    }

    @Test public void firstReadingAfterTodaysBootIsExact() {
        PhoneDailyStepPolicy.Update value = PhoneDailyStepPolicy.update(
            0, 42, -1, false, true, true, false);
        assertEquals(42, value.steps());
    }
}
