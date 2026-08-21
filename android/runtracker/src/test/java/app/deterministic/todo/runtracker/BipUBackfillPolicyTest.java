package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import org.junit.Test;

public class BipUBackfillPolicyTest {
    private static final long HOUR = 3_600_000L;

    @Test public void firstImportRequestsSevenDays() {
        BipUBackfillPolicy.Request request = BipUBackfillPolicy.request(10 * 24 * HOUR, null);
        assertEquals(7 * 24, request.requestedHours());
        assertFalse(request.historyCapApplied());
    }

    @Test public void reconnectOverlapsLastStoredHour() {
        long now = 100 * HOUR;
        BipUBackfillPolicy.Request request = BipUBackfillPolicy.request(now, 95 * HOUR);
        assertEquals(6, request.requestedHours());
        assertEquals(94 * HOUR, request.sinceMillis());
        assertFalse(request.historyCapApplied());
    }

    @Test public void veryOldHistoryIsBoundedAndDeclared() {
        long now = 30 * 24 * HOUR;
        BipUBackfillPolicy.Request request = BipUBackfillPolicy.request(now, HOUR);
        assertEquals(7 * 24, request.requestedHours());
        assertTrue(request.historyCapApplied());
    }
}
