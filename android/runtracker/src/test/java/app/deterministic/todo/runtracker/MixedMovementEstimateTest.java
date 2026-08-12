package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class MixedMovementEstimateTest {
    @Test public void separatesWalkingRunningAndVehicleSteps() {
        MixedMovementEstimate estimate = MixedMovementEstimate.calculate(
            1000, 1000, 100, 500, 0.70, 1.10, 70);
        assertEquals(1870.0, estimate.distanceMeters(), 0.001);
        assertEquals(500, estimate.excludedSteps());
        assertEquals(1000, estimate.walkingSteps());
        assertEquals(1000, estimate.runningSteps());
        assertEquals(100, estimate.unknownSteps());
        assertEquals(103.95, estimate.activeCalories(), 0.001);
    }
}
