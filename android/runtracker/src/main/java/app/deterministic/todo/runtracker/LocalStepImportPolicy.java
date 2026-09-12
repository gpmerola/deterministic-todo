package app.deterministic.todo.runtracker;

/** Stable UTC buckets make overlapping reads and retries idempotent. */
final class LocalStepImportPolicy {
    static final long MINUTE = 60_000;
    static final long LOOKBACK = 9L * 24 * 60 * MINUTE;
    record Window(long start, long end) {}

    private LocalStepImportPolicy() {}

    static long nextMinute(long now) { return Math.floorDiv(now, MINUTE) * MINUTE + MINUTE; }

    static Window window(long cutover, long importedThrough, long now) {
        long end = Math.floorDiv(now, MINUTE) * MINUTE;
        long overlap = importedThrough <= 0 ? cutover : importedThrough - 120 * MINUTE;
        return new Window(Math.max(Math.max(cutover, overlap), end - LOOKBACK), end);
    }

    static boolean valid(long start, long end, long steps, Window window) {
        return start % MINUTE == 0 && end - start == MINUTE && steps >= 0
            && start >= window.start && end <= window.end;
    }
}
