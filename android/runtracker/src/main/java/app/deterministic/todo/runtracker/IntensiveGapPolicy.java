package app.deterministic.todo.runtracker;

final class IntensiveGapPolicy {
    static final long EXPECTED_WINDOW_MILLIS = 5_000L;
    static final long GAP_THRESHOLD_MILLIS = 15_000L;

    record Gap(boolean present, long startMillis, long endMillis, long durationMillis,
               long missingExpectedWindows) {}

    private IntensiveGapPolicy() {}

    static Gap between(long previousObservedMillis, long currentObservedMillis) {
        long duration = Math.max(0, currentObservedMillis - previousObservedMillis);
        if (previousObservedMillis <= 0 || duration <= GAP_THRESHOLD_MILLIS)
            return new Gap(false, previousObservedMillis, currentObservedMillis, duration, 0);
        long missing = Math.max(1, duration / EXPECTED_WINDOW_MILLIS - 1);
        return new Gap(true, previousObservedMillis, currentObservedMillis, duration, missing);
    }
}
