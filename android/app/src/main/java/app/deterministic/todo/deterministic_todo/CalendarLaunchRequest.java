package app.deterministic.todo.deterministic_todo;

import android.content.Intent;

/** One-shot foreground navigation. A Semble conflict notification adds only
 * the start instant of the event to open, never a title or identifier. */
public final class CalendarLaunchRequest {
    static final String EXTRA_EVENT_START = "semble_event_start";
    static final String EXTRA_SINGLE = "semble_event_single";

    private boolean pending;
    private long eventStart;
    private boolean single;

    public boolean accept(String action, String packageName) {
        return accept(action, packageName, 0, false);
    }

    public boolean acceptIntent(Intent intent, String packageName) {
        return intent != null && accept(intent.getAction(), packageName,
            intent.getLongExtra(EXTRA_EVENT_START, 0), intent.getBooleanExtra(EXTRA_SINGLE, false));
    }

    public boolean accept(String action, String packageName, long start, boolean one) {
        if (!(packageName + ".OPEN_CALENDAR").equals(action)) return false;
        pending = true;
        eventStart = Math.max(0, start);
        single = one;
        return true;
    }

    /** False, true (just the Calendar) or {start, single} for one event's day. */
    public Object consume() {
        boolean result = pending;
        pending = false;
        if (!result) return false;
        if (eventStart == 0) return true;
        java.util.Map<String, Object> target = new java.util.HashMap<>();
        target.put("start", eventStart);
        target.put("single", single);
        eventStart = 0;
        return target;
    }
}
