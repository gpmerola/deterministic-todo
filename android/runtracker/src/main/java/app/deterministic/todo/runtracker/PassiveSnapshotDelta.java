package app.deterministic.todo.runtracker;

/** Computes a safe intraday delta without treating resets or late source loss as movement. */
final class PassiveSnapshotDelta {
    record Sample(String day, long observedAtMillis, long todoSteps, double todoDistanceMeters,
                  Long fitSteps, Double fitDistanceMeters, long walkingSteps,
                  long runningSteps, long unknownSteps, long excludedSteps,
                  long stillConflictSteps) {}

    record Delta(boolean valid, String reason, long startMillis, long endMillis,
                 long durationMillis, long todoSteps, double todoDistanceMeters,
                 Long fitSteps, Double fitDistanceMeters, long walkingSteps,
                 long runningSteps, long unknownSteps, long excludedSteps,
                 long stillConflictSteps) {}

    private PassiveSnapshotDelta() {}

    static Delta between(Sample previous, Sample current) {
        if (previous == null) return invalid("no_previous_snapshot", current);
        if (!current.day().equals(previous.day())) return invalid("different_day", current);
        if (current.observedAtMillis() <= previous.observedAtMillis())
            return invalid("non_increasing_time", current);
        if (current.todoSteps() < previous.todoSteps()
            || current.todoDistanceMeters() < previous.todoDistanceMeters()
            || current.walkingSteps() < previous.walkingSteps()
            || current.runningSteps() < previous.runningSteps()
            || current.unknownSteps() < previous.unknownSteps()
            || current.excludedSteps() < previous.excludedSteps()
            || current.stillConflictSteps() < previous.stillConflictSteps())
            return invalid("todo_counter_reset", current);
        Long fitSteps = subtractNullable(current.fitSteps(), previous.fitSteps());
        Double fitDistance = subtractNullable(current.fitDistanceMeters(), previous.fitDistanceMeters());
        if ((fitSteps != null && fitSteps < 0) || (fitDistance != null && fitDistance < 0))
            return invalid("fit_counter_reset_or_source_changed", current);
        return new Delta(true, "ok", previous.observedAtMillis(), current.observedAtMillis(),
            current.observedAtMillis() - previous.observedAtMillis(),
            current.todoSteps() - previous.todoSteps(),
            current.todoDistanceMeters() - previous.todoDistanceMeters(), fitSteps, fitDistance,
            current.walkingSteps() - previous.walkingSteps(),
            current.runningSteps() - previous.runningSteps(),
            current.unknownSteps() - previous.unknownSteps(),
            current.excludedSteps() - previous.excludedSteps(),
            current.stillConflictSteps() - previous.stillConflictSteps());
    }

    private static Delta invalid(String reason, Sample current) {
        return new Delta(false, reason, current.observedAtMillis(), current.observedAtMillis(),
            0, 0, 0, null, null, 0, 0, 0, 0, 0);
    }

    private static Long subtractNullable(Long current, Long previous) {
        return current == null || previous == null ? null : current - previous;
    }

    private static Double subtractNullable(Double current, Double previous) {
        return current == null || previous == null ? null : current - previous;
    }
}
