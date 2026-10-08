package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertEquals;
import org.junit.Test;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Map;

public final class AgendaTimeZonesTest {
    @Test public void resolvesRomeWinterAndSummer() {
        assertEquals(Instant.parse("2026-01-15T09:00:00Z").toEpochMilli(),
            AgendaTimeZones.instant("2026-01-15T10:00:00", ZoneId.of("Europe/Rome")));
        assertEquals(Instant.parse("2026-07-15T08:00:00Z").toEpochMilli(),
            AgendaTimeZones.instant("2026-07-15T10:00:00", ZoneId.of("Europe/Rome")));
    }
    @Test(expected = IllegalArgumentException.class) public void rejectsSpringGap() {
        AgendaTimeZones.instant("2026-03-29T01:30:00", ZoneId.of("Europe/London"));
    }
    @Test(expected = IllegalArgumentException.class) public void rejectsAutumnAmbiguity() {
        AgendaTimeZones.instant("2026-10-25T01:30:00", ZoneId.of("Europe/London"));
    }
    @Test public void durationAndRecurrenceEndFollowZoneRules() {
        Map<String, Object> result = AgendaTimeZones.resolve("Europe/London",
            "2026-10-25T00:30:00", "2026-10-25T02:30:00", "2026-10-25");
        assertEquals(3 * 3600_000L, (long) result.get("end") - (long) result.get("start"));
        assertEquals(Instant.parse("2026-10-25T23:59:59Z").toEpochMilli(), result.get("until"));
    }
}
