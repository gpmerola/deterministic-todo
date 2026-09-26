package app.deterministic.todo.runtracker;

/** Stable bounds and progress semantics for the civil-day step goal. */
public final class DailyStepGoalPolicy {
    public static final int DEFAULT_GOAL = 10_000;
    public static final int MIN_GOAL = 1_000;
    public static final int MAX_GOAL = 100_000;

    private DailyStepGoalPolicy() {}

    public static int normalize(int value) {
        return Math.max(MIN_GOAL, Math.min(MAX_GOAL, value));
    }

    public static float progress(long steps, int goal) {
        if (goal <= 0) return 0f;
        return Math.max(0f, Math.min(1f, (float) steps / goal));
    }
}
