package app.deterministic.todo.runtracker;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.List;

public class LocalDailyMovementModelTest {
    private final MovementProfile profile = new MovementProfile(70, .7, 1.1);
    private LocalStepMinute minute(long start, long steps) {
        var value = new LocalStepMinute(); value.startMillis = start; value.steps = steps; return value;
    }

    @Test public void walkingAndRunningUseDifferentPersonalStrides() {
        var result = LocalDailyMovementModel.calculate(List.of(minute(0, 100), minute(60_000, 100)),
            List.of(new ActivityTimeline.Event(0, "walking"), new ActivityTimeline.Event(60_000, "running")),
            List.of(), 0, 120_000, 0, profile);
        assertEquals(180, result.meters(), .0001);
        assertEquals(10.15, result.activeCalories(), .0001);
        assertEquals(100, result.runningSteps());
    }

    @Test public void gpsReplacesEstimateAndDuplicateSessionIsNotAdded() {
        var segment = new LocalDailyMovementModel.GpsSegment(0, 60_000, 90, "walk");
        var result = LocalDailyMovementModel.calculate(List.of(minute(0, 100)), List.of(),
            List.of(segment, segment), 0, 60_000, 0, profile);
        assertEquals(90, result.meters(), .0001);
        assertEquals(3.15, result.activeCalories(), .0001);
    }

    @Test public void gapKeepsStepEstimateAndGpsCanExistWithoutPhoneSteps() {
        var result = LocalDailyMovementModel.calculate(List.of(minute(0, 100)), List.of(),
            List.of(new LocalDailyMovementModel.GpsSegment(0, 30_000, 45, "walk"),
                new LocalDailyMovementModel.GpsSegment(60_000, 120_000, 100, "run")),
            0, 120_000, 0, profile);
        assertEquals(180, result.meters(), .0001); // 45 GPS + 35 estimate + 100 GPS
    }

    @Test public void cutoverPreservesLegacyWithoutReusingOldGps() {
        var result = LocalDailyMovementModel.calculate(List.of(minute(60_000, 100)), List.of(),
            List.of(new LocalDailyMovementModel.GpsSegment(0, 60_000, 800, "walk")),
            60_000, 120_000, 200, profile);
        assertEquals(210, result.meters(), .0001);
    }

    @Test public void gpsCrossingDayBoundaryIsClippedWithoutDoubleCounting() {
        var segment = new LocalDailyMovementModel.GpsSegment(30_000, 90_000, 100, "run");
        var a = LocalDailyMovementModel.calculate(List.of(), List.of(), List.of(segment), 0, 60_000, 0, profile);
        var b = LocalDailyMovementModel.calculate(List.of(), List.of(), List.of(segment), 60_000, 120_000, 0, profile);
        assertEquals(100, a.meters() + b.meters(), .0001);
    }

    @Test public void standingConflictIsUncertainButVehicleIsExcludedFromDistance() {
        var result = LocalDailyMovementModel.calculate(List.of(minute(0, 100), minute(60_000, 100)),
            List.of(new ActivityTimeline.Event(0, "still"), new ActivityTimeline.Event(60_000, "vehicle")),
            List.of(), 0, 120_000, 0, profile);
        assertEquals(70, result.meters(), .0001);
        assertEquals(100, result.unknownSteps());
    }

    @Test(expected = IllegalArgumentException.class) public void invalidProfileRejected() {
        new MovementProfile(Double.NaN, .7, 1.1);
    }
}
