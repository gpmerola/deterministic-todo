package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class AgendaBackgroundTest {
    @Test public void unknownDartResultsAreRetried() {
        assertEquals(AgendaBackground.Outcome.DONE, AgendaBackground.parse("done"));
        assertEquals(AgendaBackground.Outcome.STOP, AgendaBackground.parse("stop"));
        assertEquals(AgendaBackground.Outcome.RETRY, AgendaBackground.parse("retry"));
        assertEquals(AgendaBackground.Outcome.RETRY, AgendaBackground.parse(null));
        assertEquals(AgendaBackground.Outcome.RETRY, AgendaBackground.parse(true));
    }

    @Test public void retryCausesAreContentFree() {
        assertEquals(AgendaBackground.Outcome.RETRY, AgendaBackground.parse("retry:mirror_no_access"));
        assertEquals("mirror_no_access", AgendaBackground.cause("retry:mirror_no_access"));
        assertEquals("error_supabase_42501", AgendaBackground.cause("retry:error_supabase_42501"));
        assertEquals("unspecified", AgendaBackground.cause("retry"));
        assertEquals("null_result", AgendaBackground.cause(null));
        assertEquals("unexpected_result", AgendaBackground.cause(true));
        assertEquals("unexpected_result", AgendaBackground.cause("retry:Riunione con Mario"));
        assertEquals("unexpected_result", AgendaBackground.cause("other"));
    }

    @Test public void onlyIdenticalCalendarStatesJoinARun() {
        assertEquals(AgendaBackground.joinKey("calendar", "ab"), AgendaBackground.joinKey("calendar", "ab"));
        org.junit.Assert.assertNotEquals(
            AgendaBackground.joinKey("calendar", "ab"), AgendaBackground.joinKey("calendar", "cd"));
        org.junit.Assert.assertNotEquals(
            AgendaBackground.joinKey("calendar", "ab"), AgendaBackground.joinKey("periodic", "ab"));
    }

    @Test public void retriesBackOffUpToAnHour() {
        assertEquals(120_000L, AgendaBackground.retryDelayMs(0));
        assertEquals(240_000L, AgendaBackground.retryDelayMs(1));
        assertEquals(480_000L, AgendaBackground.retryDelayMs(2));
        assertEquals(3_600_000L, AgendaBackground.retryDelayMs(5));
        assertEquals(3_600_000L, AgendaBackground.retryDelayMs(40));
    }

    @Test public void fingerprintsAreLowerHex() {
        assertEquals("00ff10", AgendaBackground.hex(new byte[] {0, (byte) 0xff, 0x10}));
    }
}
