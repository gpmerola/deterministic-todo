package app.deterministic.todo.runtracker;

final class StepCounterSession {
    record Reading(long steps, String status) {}

    private Float lastRaw;
    private long steps;

    StepCounterSession() { this(0); }
    StepCounterSession(long initialSteps) { steps = Math.max(0, initialSteps); }

    Reading accept(float raw) {
        if (!Float.isFinite(raw) || raw < 0) return new Reading(steps, "invalid");
        if (lastRaw == null) {
            lastRaw = raw;
            return new Reading(steps, "active");
        }
        if (raw < lastRaw) {
            lastRaw = raw;
            return new Reading(steps, "counter_reset");
        }
        steps += Math.max(0L, (long) Math.floor(raw - lastRaw));
        lastRaw = raw;
        return new Reading(steps, "active");
    }

    long steps() { return steps; }
}
