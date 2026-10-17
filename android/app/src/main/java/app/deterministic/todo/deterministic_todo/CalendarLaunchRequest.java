package app.deterministic.todo.deterministic_todo;

/** One-shot foreground navigation, with no event data or persisted identifiers. */
public final class CalendarLaunchRequest {
    private boolean pending;

    public boolean accept(String action, String packageName) {
        if (!(packageName + ".OPEN_CALENDAR").equals(action)) return false;
        pending = true;
        return true;
    }

    public boolean consume() {
        boolean result = pending;
        pending = false;
        return result;
    }
}
