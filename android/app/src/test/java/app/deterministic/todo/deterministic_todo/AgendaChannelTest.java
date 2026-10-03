package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;

public final class AgendaChannelTest {
    @Test public void keepsOnlyMeetingUrlsFromInviteBodies() {
        String body = "<html>Join <https://teams.microsoft.com/l/meetup-join/abc?x=1> "
            + "or https://example.org/privacy and https://kcl.zoom.us/j/123</html>";
        assertEquals("https://teams.microsoft.com/l/meetup-join/abc?x=1\nhttps://kcl.zoom.us/j/123",
            AgendaChannel.links(body));
        assertNull(AgendaChannel.links("Patient review, room 4"));
        assertNull(AgendaChannel.links(null));
    }

    @Test public void allDayInstancesKeepTheirCivilDate() {
        ZoneId london = ZoneId.of("Europe/London");
        long utcMidnight = LocalDate.of(2026, 10, 5).atStartOfDay(ZoneOffset.UTC)
            .toInstant().toEpochMilli();
        long local = AgendaChannel.localMidnightOfUtcDay(utcMidnight, london);
        assertEquals(LocalDate.of(2026, 10, 5).atStartOfDay(london).toInstant().toEpochMilli(), local);
        assertEquals(utcMidnight, AgendaChannel.utcMidnightOfLocalDay(local, london));
    }
}
