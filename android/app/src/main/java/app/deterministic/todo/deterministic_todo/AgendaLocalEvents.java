package app.deterministic.todo.deterministic_todo;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CalendarContract.Events;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Full events of Todo's own phone calendar for the Supabase backup (build
 * 227), and their restore on a new phone. Unlike the Agenda query these
 * keep notes and repetition rules: the calendar exists nowhere else.
 * Nothing here is logged.
 */
final class AgendaLocalEvents {
    private AgendaLocalEvents() {}

    private static final String[] COLUMNS = {
        Events._ID, Events.TITLE, Events.DTSTART, Events.DTEND, Events.DURATION,
        Events.ALL_DAY, Events.EVENT_TIMEZONE, Events.EVENT_END_TIMEZONE,
        Events.EVENT_LOCATION, Events.DESCRIPTION, Events.RRULE, Events.RDATE,
        Events.EXRULE, Events.EXDATE, Events.ORIGINAL_ID,
        Events.ORIGINAL_INSTANCE_TIME, Events.ORIGINAL_ALL_DAY, Events.STATUS,
        Events.AVAILABILITY,
    };

    /** JSON keys, in the order of [COLUMNS]. */
    private static final String[] KEYS = {
        "id", "title", "dtstart", "dtend", "duration", "all_day", "tz", "end_tz",
        "location", "description", "rrule", "rdate", "exrule", "exdate",
        "original_id", "original_instance_time", "original_all_day", "status",
        "availability",
    };

    static List<Map<String, Object>> read(Context context, String calendarId) {
        List<Map<String, Object>> rows = new ArrayList<>();
        try (Cursor cursor = context.getContentResolver().query(Events.CONTENT_URI, COLUMNS,
                Events.CALENDAR_ID + " = ? AND " + Events.DELETED + " = 0",
                new String[] {calendarId}, Events._ID + " ASC")) {
            if (cursor == null) return rows;
            while (cursor.moveToNext()) {
                Map<String, Object> row = new HashMap<>();
                for (int i = 0; i < COLUMNS.length; i++) {
                    if (cursor.isNull(i)) continue;
                    switch (cursor.getType(i)) {
                        case Cursor.FIELD_TYPE_INTEGER:
                            row.put(KEYS[i], cursor.getLong(i));
                            break;
                        default:
                            row.put(KEYS[i], cursor.getString(i));
                    }
                }
                rows.add(row);
            }
        }
        return rows;
    }

    /**
     * Same event for the restore: an event already in the calendar (a
     * second restore, or one created meanwhile) is not inserted again.
     */
    static String signature(Map<String, Object> event) {
        return String.valueOf(event.get("title")) + '\u001f' + number(event.get("dtstart"))
            + '\u001f' + event.get("rrule") + '\u001f'
            + number(event.get("original_instance_time"));
    }

    /** Series and single events first, then their changed occurrences. */
    static List<Map<String, Object>> restoreOrder(List<Map<String, Object>> events) {
        List<Map<String, Object>> ordered = new ArrayList<>();
        for (Map<String, Object> event : events) {
            if (event.get("original_id") == null) ordered.add(event);
        }
        for (Map<String, Object> event : events) {
            if (event.get("original_id") != null) ordered.add(event);
        }
        return ordered;
    }

    /** Inserts the events missing from [calendarId]; returns how many. */
    static int restore(Context context, String calendarId, List<Map<String, Object>> events) {
        ContentResolver resolver = context.getContentResolver();
        Map<String, Long> existing = new HashMap<>();
        List<Map<String, Object>> current = read(context, calendarId);
        Map<Long, Map<String, Object>> currentById = new HashMap<>();
        for (Map<String, Object> row : current) currentById.put(number(row.get("id")), row);
        for (Map<String, Object> row : current) {
            Map<String, Object> parent = currentById.get(number(row.get("original_id")));
            existing.put(signature(withParentSignature(row, parent)), number(row.get("id")));
        }
        // Old id (from the backup) → id on this phone.
        Map<Long, Long> ids = new HashMap<>();
        Map<Long, Map<String, Object>> byOldId = new HashMap<>();
        for (Map<String, Object> event : events) byOldId.put(number(event.get("id")), event);
        Set<String> done = new HashSet<>();
        int inserted = 0;
        for (Map<String, Object> event : restoreOrder(events)) {
            Long oldId = number(event.get("id"));
            Long originalId = number(event.get("original_id"));
            String key = signature(withParentSignature(event, byOldId.get(originalId)));
            if (!done.add(key)) continue;
            Long present = existing.get(key);
            if (present != null) {
                ids.put(oldId, present);
                continue;
            }
            Uri uri;
            if (originalId == null) {
                uri = resolver.insert(Events.CONTENT_URI, values(calendarId, event, false));
            } else {
                Long parent = ids.get(originalId);
                if (parent == null) continue;
                uri = resolver.insert(
                    ContentUris.withAppendedId(Events.CONTENT_EXCEPTION_URI, parent),
                    values(calendarId, event, true));
            }
            if (uri != null) {
                ids.put(oldId, ContentUris.parseId(uri));
                inserted++;
            }
        }
        return inserted;
    }

    /**
     * Changed occurrences are told apart by their series too: two series
     * may have exceptions at the same instant.
     */
    private static Map<String, Object> withParentSignature(Map<String, Object> event,
                                                           Map<String, Object> parent) {
        if (parent == null) return event;
        Map<String, Object> copy = new HashMap<>(event);
        copy.put("title", event.get("title") + "\u001e" + signature(parent));
        return copy;
    }

    private static ContentValues values(String calendarId, Map<String, Object> event,
                                        boolean exception) {
        ContentValues values = new ContentValues();
        if (!exception) values.put(Events.CALENDAR_ID, Long.parseLong(calendarId));
        putString(values, Events.TITLE, event.get("title"));
        putLong(values, Events.DTSTART, event.get("dtstart"));
        boolean recurring = event.get("rrule") != null || event.get("rdate") != null;
        if (recurring && !exception) {
            Object duration = event.get("duration");
            if (duration == null) {
                Long start = number(event.get("dtstart"));
                Long end = number(event.get("dtend"));
                duration = start == null || end == null ? "PT1H" : "P" + (end - start) / 1000 + "S";
            }
            putString(values, Events.DURATION, duration);
        } else {
            Long end = number(event.get("dtend"));
            if (end != null) {
                values.put(Events.DTEND, end);
            } else {
                putString(values, Events.DURATION, event.get("duration"));
            }
        }
        putLong(values, Events.ALL_DAY, event.get("all_day"));
        Object zone = event.get("tz");
        values.put(Events.EVENT_TIMEZONE, zone == null ? "UTC" : zone.toString());
        putString(values, Events.EVENT_END_TIMEZONE, event.get("end_tz"));
        putString(values, Events.EVENT_LOCATION, event.get("location"));
        putString(values, Events.DESCRIPTION, event.get("description"));
        putLong(values, Events.STATUS, event.get("status"));
        putLong(values, Events.AVAILABILITY, event.get("availability"));
        if (exception) {
            putLong(values, Events.ORIGINAL_INSTANCE_TIME, event.get("original_instance_time"));
            putLong(values, Events.ORIGINAL_ALL_DAY, event.get("original_all_day"));
        } else {
            putString(values, Events.RRULE, event.get("rrule"));
            putString(values, Events.RDATE, event.get("rdate"));
            putString(values, Events.EXRULE, event.get("exrule"));
            putString(values, Events.EXDATE, event.get("exdate"));
        }
        return values;
    }

    private static void putString(ContentValues values, String column, Object value) {
        if (value != null) values.put(column, value.toString());
    }

    private static void putLong(ContentValues values, String column, Object value) {
        Long number = number(value);
        if (number != null) values.put(column, number);
    }

    /** JSON numbers arrive as Integer or Long, ids sometimes as strings. */
    static Long number(Object value) {
        if (value instanceof Number) return ((Number) value).longValue();
        if (value instanceof String) {
            try {
                return Long.parseLong((String) value);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }
}
