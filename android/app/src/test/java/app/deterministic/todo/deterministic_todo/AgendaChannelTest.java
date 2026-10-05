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

    @Test public void showsOriginalTimesOnlyForAnotherOffset() {
        ZoneId london = ZoneId.of("Europe/London");
        long begin = java.time.ZonedDateTime.of(2026, 10, 22, 12, 0, 0, 0, london)
            .toInstant().toEpochMilli();
        long end = begin + 3_600_000;
        assertEquals("13:00–14:00", AgendaChannel.eventZoneTimes(begin, end, "Europe/Rome", london));
        assertNull(AgendaChannel.eventZoneTimes(begin, end, "Europe/London", london));
        assertNull(AgendaChannel.eventZoneTimes(begin, end, "Europe/Lisbon", london));
        assertNull(AgendaChannel.eventZoneTimes(begin, end, "Not/AZone", london));
        assertNull(AgendaChannel.eventZoneTimes(begin, end, null, london));
    }

    @Test public void foldsCaseAndAccentsForSearch() {
        assertEquals("attivita perche", AgendaChannel.fold("Attività PERCHÉ"));
        assertEquals("100% sicuro_x", AgendaChannel.fold("100% sicuro_x"));
        assertEquals("nandu", AgendaChannel.fold("Ñandú"));
    }

    @Test public void prefilterIsASupersetAndKeepsWildcardsLiteral() {
        assertEquals("_tt_v_t_", AgendaChannel.likePrefilter("attivita"));
        assertEquals("100\\% s___r_\\_x\\\\", AgendaChannel.likePrefilter("100% sicuro_x\\"));
        assertEquals("w_rd r___d", AgendaChannel.likePrefilter("ward round"));
    }

    @Test public void onlyRealAnswersCountAsAnswered() {
        assertEquals(true, AgendaChannel.answered(1));
        assertEquals(true, AgendaChannel.answered(2));
        assertEquals(true, AgendaChannel.answered(4));
        assertEquals(false, AgendaChannel.answered(0));
        assertEquals(false, AgendaChannel.answered(3));
        assertEquals(false, AgendaChannel.answered(-1));
    }

    @Test public void deviceZoneIsIanaWithOffset() {
        var value = AgendaChannel.deviceZone(ZoneId.of("Europe/London"),
            java.time.Instant.parse("2026-10-03T12:00:00Z"));
        assertEquals("Europe/London", value.get("id"));
        assertEquals(3600, value.get("offsetSeconds"));
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
