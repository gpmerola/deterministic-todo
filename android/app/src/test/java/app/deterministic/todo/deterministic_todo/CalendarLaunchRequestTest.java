package app.deterministic.todo.deterministic_todo;

import org.junit.Test;
import static org.junit.Assert.*;

public class CalendarLaunchRequestTest {
    @Test public void coldAndWarmRequestsAreConsumedOnce() {
        CalendarLaunchRequest request = new CalendarLaunchRequest();
        assertFalse(request.consume());
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev"));
        assertTrue(request.consume());
        assertFalse(request.consume());
        assertTrue(request.accept("test.dev.OPEN_CALENDAR", "test.dev"));
        assertTrue(request.consume());
    }

    @Test public void otherPackagesAndNormalLaunchesCannotRequestCalendar() {
        CalendarLaunchRequest request = new CalendarLaunchRequest();
        assertFalse(request.accept("test.OPEN_CALENDAR", "test.dev"));
        assertFalse(request.accept("android.intent.action.MAIN", "test.dev"));
        assertFalse(request.accept(null, "test.dev"));
        assertFalse(request.consume());
    }
}
