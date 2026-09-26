package app.deterministic.todo.deterministic_todo;

/** An old successful cycle cannot describe a newer unfinished cycle. */
public final class TodoSyncTimeline {
    private TodoSyncTimeline() {}

    public static boolean unfinished(String started, String completed,
                                     String failed, String cancelled) {
        if (started == null) return false;
        for (String ended : new String[] { completed, failed, cancelled }) {
            if (ended != null && ended.compareTo(started) >= 0) return false;
        }
        return true;
    }
}
