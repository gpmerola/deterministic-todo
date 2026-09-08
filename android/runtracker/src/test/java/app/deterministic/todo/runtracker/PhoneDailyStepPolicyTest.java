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
            0, 42, -1, false, false, true, false);
        assertEquals(42, value.steps());
        assertEquals("initial_boot_today", value.reason());
    }

    @Test public void returningToObservedDayAndZonePreservesSubtotal() {
        PhoneDailyStepPolicy.Update returned = PhoneDailyStepPolicy.update(
            320, 900, 700, true, false, false, false);
        assertEquals(320, returned.steps());
        assertEquals(0, returned.delta());
        assertEquals("civil_boundary_baseline", returned.reason());
        PhoneDailyStepPolicy.Update next = PhoneDailyStepPolicy.update(
            returned.steps(), 910, 900, true, true, false, false);
        assertEquals(330, next.steps());
        assertEquals("counted", next.reason());
    }

    @Test public void rebootPreservesSubtotalAndResumesWithoutCountingGap() {
        PhoneDailyStepPolicy.Update reboot = PhoneDailyStepPolicy.update(
            320, 50, 700, false, true, true, false);
        assertEquals(320, reboot.steps());
        assertEquals("boot_baseline", reboot.reason());
        assertEquals(330, PhoneDailyStepPolicy.update(
            reboot.steps(), 60, 50, true, true, true, false).steps());
    }

    @Test public void resetAndDuplicateNeverAddNegativeOrRepeatedSteps() {
        PhoneDailyStepPolicy.Update reset = PhoneDailyStepPolicy.update(
            320, 10, 700, true, true, false, false);
        assertEquals(320, reset.steps());
        assertEquals("counter_reset_baseline", reset.reason());
        PhoneDailyStepPolicy.Update duplicate = PhoneDailyStepPolicy.update(
            reset.steps(), 10, 10, true, true, false, false);
        assertEquals(320, duplicate.steps());
        assertEquals("unchanged", duplicate.reason());
    }

    @Test public void initialReadingFromEarlierBootCannotReconstructToday() {
        PhoneDailyStepPolicy.Update value = PhoneDailyStepPolicy.update(
            0, 5000, -1, false, false, false, false);
        assertEquals(0, value.steps());
        assertEquals("initial_baseline", value.reason());
    }

    @Test public void missingBaselineNeverAddsWholeBootToExistingSubtotal() {
        assertEquals(320, PhoneDailyStepPolicy.update(
            320, 5000, -1, false, false, true, false).steps());
    }

    @Test(expected = IllegalArgumentException.class)
    public void invalidCounterCannotBecomeBaseline() {
        PhoneDailyStepPolicy.update(320, Float.NaN, 700, true, true, false, false);
    }
}
