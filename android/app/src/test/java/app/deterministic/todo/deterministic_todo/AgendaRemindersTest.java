package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.*;
import org.junit.Test;

public final class AgendaRemindersTest {
    @Test public void lateNewEventsDoNotCreateRetroactiveNotifications() {
        assertFalse(AgendaReminders.shouldKeep(100, 200, 150, false));
        assertTrue(AgendaReminders.shouldKeep(100, 200, 50, false));
    }
    @Test public void refreshKeepsAnAlreadyScheduledDueAlarm() {
        assertTrue(AgendaReminders.shouldKeep(100, 200, 150, true));
        assertFalse(AgendaReminders.shouldKeep(100, 200, 200, true));
        assertFalse(AgendaReminders.shouldKeep(100, 200, 250, true));
    }
}
