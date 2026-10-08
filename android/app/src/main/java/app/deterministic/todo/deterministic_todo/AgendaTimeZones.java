package app.deterministic.todo.deterministic_todo;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Civil input must identify exactly one instant; never guess at DST transitions. */
final class AgendaTimeZones {
    private AgendaTimeZones() {}
    static long instant(String value, ZoneId zone) {
        LocalDateTime wall = LocalDateTime.parse(value);
        List<ZoneOffset> offsets = zone.getRules().getValidOffsets(wall);
        if (offsets.size() != 1) throw new IllegalArgumentException("Ambiguous or absent time");
        return wall.toInstant(offsets.get(0)).toEpochMilli();
    }
    static Map<String, Object> resolve(String id, String start, String end, String until) {
        ZoneId zone = ZoneId.of(id);
        Map<String, Object> result = new HashMap<>();
        long first = instant(start, zone), last = instant(end, zone);
        if (last <= first) throw new IllegalArgumentException("Invalid range");
        result.put("start", first);
        result.put("end", last);
        if (until != null) result.put("until", LocalDate.parse(until).plusDays(1)
            .atStartOfDay(zone).toInstant().minusSeconds(1).toEpochMilli());
        return result;
    }
}
