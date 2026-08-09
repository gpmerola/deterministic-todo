package app.deterministic.todo.runtracker;

/** Keeps step/GPS policy out of the Android service lifecycle code. */
final class StepMotionGate {
    record Evidence(boolean stepObserved, boolean stepRequired) {}

    private long previousSteps;

    StepMotionGate(long initialSteps) {
        previousSteps = Math.max(0, initialSteps);
    }

    Evidence observe(long currentSteps, String activityType, String sensorStatus) {
        long safeSteps = Math.max(0, currentSteps);
        boolean observed = safeSteps > previousSteps;
        previousSteps = safeSteps;
        boolean required = "walk".equals(activityType) && "active".equals(sensorStatus);
        return new Evidence(observed, required);
    }
}
