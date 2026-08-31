package app.deterministic.todo.runtracker;

final class BipAvailabilityPolicy {
    private static final long STALE_AFTER_MS = 6L * 60 * 60 * 1000;

    private BipAvailabilityPolicy() {}

    static String status(Long latestSampleMillis, long observedAtMillis) {
        if (latestSampleMillis == null) return "no_samples_in_measurement_window";
        return observedAtMillis - latestSampleMillis > STALE_AFTER_MS
            ? "local_samples_stale" : "local_samples_current";
    }

    static String recoveryAction(String status) {
        return "local_samples_current".equals(status)
            ? "none" : "explicit_watch_import_required";
    }
}
