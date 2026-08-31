package app.deterministic.todo.runtracker;

import org.junit.Test;

import static org.junit.Assert.*;

public final class PassiveSnapshotDeltaTest {
    @Test public void calculatesAllComparableDeltas() {
        PassiveSnapshotDelta.Sample before = sample("2026-08-18", 1_000, 100, 72, 100L, 65.0,
            40, 10, 50, 0, 5);
        PassiveSnapshotDelta.Sample after = sample("2026-08-18", 4_000, 180, 135, 175L, 110.0,
            70, 20, 85, 5, 8);

        PassiveSnapshotDelta.Delta delta = PassiveSnapshotDelta.between(before, after);

        assertTrue(delta.valid());
        assertEquals(3_000, delta.durationMillis());
        assertEquals(80, delta.todoSteps());
        assertEquals(63, delta.todoDistanceMeters(), 0.0001);
        assertEquals(Long.valueOf(75), delta.fitSteps());
        assertEquals(Double.valueOf(45), delta.fitDistanceMeters());
        assertEquals(30, delta.walkingSteps());
        assertEquals(10, delta.runningSteps());
        assertEquals(35, delta.unknownSteps());
        assertEquals(5, delta.excludedSteps());
        assertEquals(3, delta.stillConflictSteps());
    }

    @Test public void rejectsDayBoundaryAndCounterReset() {
        PassiveSnapshotDelta.Sample before = sample("2026-08-17", 1_000, 100, 72, 100L, 65.0,
            40, 10, 50, 0, 5);
        PassiveSnapshotDelta.Sample nextDay = sample("2026-08-18", 4_000, 10, 7.2, 10L, 6.5,
            4, 1, 5, 0, 0);
        assertEquals("different_day", PassiveSnapshotDelta.between(before, nextDay).reason());

        PassiveSnapshotDelta.Sample reset = sample("2026-08-17", 4_000, 90, 65, 90L, 60.0,
            35, 10, 45, 0, 4);
        assertEquals("todo_counter_reset", PassiveSnapshotDelta.between(before, reset).reason());
    }

    @Test public void keepsMissingFitValuesExplicitlyNull() {
        PassiveSnapshotDelta.Sample before = sample("2026-08-18", 1_000, 100, 72, null, null,
            40, 10, 50, 0, 5);
        PassiveSnapshotDelta.Sample after = sample("2026-08-18", 4_000, 110, 79, 108L, 70.0,
            45, 10, 55, 0, 6);
        PassiveSnapshotDelta.Delta delta = PassiveSnapshotDelta.between(before, after);
        assertTrue(delta.valid());
        assertNull(delta.fitSteps());
        assertNull(delta.fitDistanceMeters());
    }

    private static PassiveSnapshotDelta.Sample sample(String day, long observedAt, long todoSteps,
                                                        double todoDistance, Long fitSteps,
                                                        Double fitDistance, long walking, long running,
                                                        long unknown, long excluded, long still) {
        return new PassiveSnapshotDelta.Sample(day, observedAt, todoSteps, todoDistance,
            fitSteps, fitDistance, walking, running, unknown, excluded, still);
    }
}
