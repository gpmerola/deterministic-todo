package app.deterministic.todo.deterministic_todo;

import org.junit.Test;
import static org.junit.Assert.*;

public class CalendarLaunchRequestTest {
    @Test public void coldAndWarmRequestsAreConsumedOnce() {
        CalendarLaunchRequest request = new CalendarLaunchRequest();
        assertEquals(false, request.consume());
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev"));
        assertEquals(true, request.consume());
        assertEquals(false, request.consume());
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev"));
        assertEquals(true, request.consume());
    }

    @Test public void conflictNotificationCarriesOnlyTheEventStart() {
        CalendarLaunchRequest request = new CalendarLaunchRequest();
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev", 1_800_000_000_000L, true));
        java.util.Map<?, ?> target = (java.util.Map<?, ?>) request.consume();
        assertEquals(1_800_000_000_000L, target.get("start"));
        assertEquals(true, target.get("single"));
        assertEquals(2, target.size());
        assertEquals(false, request.consume());
        // A later plain launch does not reuse the old target.
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev"));
        assertEquals(true, request.consume());
    }

    @Test public void otherPackagesAndNormalLaunchesCannotRequestCalendar() {
        CalendarLaunchRequest request = new CalendarLaunchRequest();
        assertFalse(request.accept("test.OPEN_CALENDAR", "test.dev"));
        assertFalse(request.accept("android.intent.action.MAIN", "test.dev"));
        assertFalse(request.accept(null, "test.dev"));
        assertEquals(false, request.consume());
    }
}
