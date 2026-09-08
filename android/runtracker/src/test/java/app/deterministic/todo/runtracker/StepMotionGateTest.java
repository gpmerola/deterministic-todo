package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class StepMotionGateTest {
    @Test public void walkingWithActiveSensorRequiresFreshSteps() {
        StepMotionGate gate = new StepMotionGate(10);
        StepMotionGate.Evidence stationary = gate.observe(10, "walk", "active");
        assertFalse(stationary.stepObserved());
        assertTrue(stationary.stepRequired());

        StepMotionGate.Evidence moving = gate.observe(12, "walk", "active");
        assertTrue(moving.stepObserved());
        assertTrue(moving.stepRequired());
    }

    @Test public void runningAndUnavailableSensorKeepGpsFallback() {
        assertFalse(new StepMotionGate(0).observe(0, "run", "active").stepRequired());
        assertFalse(new StepMotionGate(0)
            .observe(0, "walk", "sensor_unavailable").stepRequired());
    }

    @Test public void counterResetCreatesNewBaselineWithoutFalseMovement() {
        StepMotionGate gate = new StepMotionGate(100);
        assertFalse(gate.observe(2, "walk", "counter_reset").stepObserved());
        assertTrue(gate.observe(3, "walk", "active").stepObserved());
    }
}
