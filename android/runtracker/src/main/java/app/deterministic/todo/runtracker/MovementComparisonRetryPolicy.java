package app.deterministic.todo.runtracker;

final class MovementComparisonRetryPolicy {
    private MovementComparisonRetryPolicy() {}

    static boolean retryMissingReference(int attempt) { return attempt < 4; }
    static boolean refreshAvailableReference(int attempt) { return attempt < 2; }

    static boolean retryFailure(String status, int attempt) {
        return !"permission_required".equals(status) && retryMissingReference(attempt);
    }
}
