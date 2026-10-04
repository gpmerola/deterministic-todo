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

    @Test public void fingerprintsAreLowerHex() {
        assertEquals("00ff10", AgendaBackground.hex(new byte[] {0, (byte) 0xff, 0x10}));
    }
}
