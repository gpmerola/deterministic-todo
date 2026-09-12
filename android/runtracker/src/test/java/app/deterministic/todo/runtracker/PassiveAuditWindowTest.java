package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import java.time.LocalDate;
import java.util.concurrent.TimeUnit;
import org.junit.Test;

public class PassiveAuditWindowTest {
    @Test public void passiveDebugSnapshotsRunHourly() {
        assertEquals(1, PassiveMovementAuditWorker.PERIODIC_INTERVAL_HOURS);
    }

    @Test public void auditRunsForSevenDaysAndThenExpires() {
        long start = 1_000L;
        long end = PassiveAuditWindow.endAt(start);
        assertEquals(start + TimeUnit.DAYS.toMillis(7), end);
        assertTrue(PassiveAuditWindow.active(end - 1, end));
        assertFalse(PassiveAuditWindow.active(end, end));
    }

    @Test public void avoidsAuditingYesterdayBeforeFitHasSettled() {
        LocalDate today = LocalDate.of(2026, 8, 10);
        assertEquals(today.minusDays(2), PassiveAuditWindow.completedDay(today, 1));
        assertEquals(today.minusDays(1), PassiveAuditWindow.completedDay(today, 18));
    }
}
