package app.deterministic.todo.runtracker;

/** Explicit semantics for delayed Health Connect / Google Fit observations. */
final class HealthSourceFreshness {
    static final long CURRENT_MAX_MS = 30L * 60 * 1000;
    static final long DELAYED_MAX_MS = 2L * 60 * 60 * 1000;

    private HealthSourceFreshness() {}

    static String status(Long latestValueMillis, long observedAtMillis) {
        if (latestValueMillis == null) return "missing";
        long age = Math.max(0, observedAtMillis - latestValueMillis);
        if (age <= CURRENT_MAX_MS) return "current";
        if (age <= DELAYED_MAX_MS) return "delayed";
        return "stale";
    }

    static boolean finalEnoughForComparison(String status) {
        return "current".equals(status);
    }
}
