package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class MovementEstimateTest {
    @Test public void estimatesDistanceAndWalkingCaloriesDeterministically() {
        MovementEstimate estimate = MovementEstimate.fromSteps(10_000, 0.72, 70);
        assertEquals(10_000, estimate.steps());
        assertEquals(7_200, estimate.distanceMeters(), 0.001);
        assertEquals(252, estimate.activeCalories(), 0.001);
    }

    @Test public void rejectsNegativeStepsAndInvalidProfileValues() {
        MovementEstimate estimate = MovementEstimate.fromSteps(-5, Double.NaN, 1);
        assertEquals(0, estimate.steps());
        assertEquals(0, estimate.distanceMeters(), 0.001);
        assertEquals(0, estimate.activeCalories(), 0.001);
    }
}
