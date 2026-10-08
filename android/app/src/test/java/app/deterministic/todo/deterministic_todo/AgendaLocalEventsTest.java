package app.deterministic.todo.deterministic_todo;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class AgendaLocalEventsTest {
    private static Map<String, Object> event(long id, String title, long start, Long originalId) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", id);
        row.put("title", title);
        row.put("dtstart", start);
        if (originalId != null) {
            row.put("original_id", originalId);
            row.put("original_instance_time", start);
        }
        return row;
    }

    @Test public void restoresSeriesBeforeTheirChangedOccurrences() {
        List<Map<String, Object>> ordered = AgendaLocalEvents.restoreOrder(Arrays.asList(
            event(3, "Changed", 30, 1L), event(1, "Series", 10, null), event(2, "Single", 20, null)));
        assertEquals(1L, ordered.get(0).get("id"));
        assertEquals(2L, ordered.get(1).get("id"));
        assertEquals(3L, ordered.get(2).get("id"));
    }

    @Test public void signatureIgnoresIdsSoARestoreIsIdempotent() {
        // JSON brings integers back as Integer: same event, same signature.
        Map<String, Object> fromJson = event(99, "MDT", 1_700_000_000_000L, null);
        fromJson.put("dtstart", 1_700_000_000_000L);
        assertEquals(AgendaLocalEvents.signature(event(1, "MDT", 1_700_000_000_000L, null)),
            AgendaLocalEvents.signature(fromJson));
        Map<String, Object> weekly = event(1, "MDT", 1_700_000_000_000L, null);
        weekly.put("rrule", "FREQ=WEEKLY");
        assertNotEquals(AgendaLocalEvents.signature(weekly),
            AgendaLocalEvents.signature(event(1, "MDT", 1_700_000_000_000L, null)));
    }

    @Test public void readsNumbersOfEveryJsonShape() {
        assertEquals(Long.valueOf(5), AgendaLocalEvents.number(5));
        assertEquals(Long.valueOf(5), AgendaLocalEvents.number(5L));
        assertEquals(Long.valueOf(5), AgendaLocalEvents.number("5"));
        assertNull(AgendaLocalEvents.number("x"));
        assertNull(AgendaLocalEvents.number(null));
    }
}
