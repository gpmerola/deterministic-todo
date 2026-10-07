package app.deterministic.todo.deterministic_todo;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CalendarContract;
import android.provider.CalendarContract.Events;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

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
        Events.AVAILABILITY, Events.CUSTOM_APP_URI,
    };

    /** JSON keys, in the order of [COLUMNS]. */
    private static final String[] KEYS = {
        "id", "title", "dtstart", "dtend", "duration", "all_day", "tz", "end_tz",
        "location", "description", "rrule", "rdate", "exrule", "exdate",
        "original_id", "original_instance_time", "original_all_day", "status",
        "availability", "copy_key",
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
        Set<Long> keyed = new HashSet<>();
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
                if (keyed.add(parent)) keySeries(context, calendarId, parent);
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
     * The provider pairs an exception with its series through `_sync_id`.
     * A series on a local calendar has none, and an exception written
     * against it removes every other occurrence from Instances: a restored
     * series showed only its changed occurrences. Like device_calendar_plus
     * 0.9 (#153), give the series a key first, as the stand-in sync adapter
     * of the local account (the column is read-only otherwise). An existing
     * key is kept; the provider copies a new one to exceptions already
     * linked by `original_id`.
     */
    static void keySeries(Context context, String calendarId, long seriesId) {
        ContentResolver resolver = context.getContentResolver();
        String accountName;
        String accountType;
        try (Cursor calendar = resolver.query(CalendarContract.Calendars.CONTENT_URI,
                new String[] {CalendarContract.Calendars.ACCOUNT_NAME,
                    CalendarContract.Calendars.ACCOUNT_TYPE},
                CalendarContract.Calendars._ID + " = ?", new String[] {calendarId}, null)) {
            if (calendar == null || !calendar.moveToFirst()) return;
            accountName = calendar.getString(0);
            accountType = calendar.getString(1);
        }
        // Synced calendars belong to their adapter: never write their keys.
        if (!CalendarContract.ACCOUNT_TYPE_LOCAL.equals(accountType)) return;
        Uri asAdapter = Events.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
            .build();
        ContentValues key = new ContentValues();
        key.put(Events._SYNC_ID, "todo-series:" + UUID.randomUUID());
        resolver.update(asAdapter, key,
            Events._ID + " = ? AND " + Events._SYNC_ID + " IS NULL",
            new String[] {Long.toString(seriesId)});
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
        // CONTENT_EXCEPTION_URI inherits the parent recurrence and requires
        // DURATION, never DTEND (the provider rejects both together).
        if (recurring || exception) {
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
        putString(values, Events.CUSTOM_APP_URI, event.get("copy_key"));
        if (exception) {
            putLong(values, Events.ORIGINAL_INSTANCE_TIME, event.get("original_instance_time"));
            // The provider derives ORIGINAL_ALL_DAY from the parent and rejects
            // attempts to overwrite it through CONTENT_EXCEPTION_URI.
        } else {
            putString(values, Events.RRULE, event.get("rrule"));
            putString(values, Events.RDATE, event.get("rdate"));
            putString(values, Events.EXRULE, event.get("exrule"));
            putString(values, Events.EXDATE, event.get("exdate"));
        }
        return values;
    }

    /** Stable private copy identity survives a crash between provider and SQLite writes. */
    static synchronized String copy(Context context, String calendarId, Map<String, Object> event) {
        ContentResolver resolver = context.getContentResolver();
        try (Cursor calendar = resolver.query(android.provider.CalendarContract.Calendars.CONTENT_URI,
                new String[] {android.provider.CalendarContract.Calendars._ID},
                "_id = ? AND account_type = ? AND account_name = ?",
                new String[] {calendarId, "LOCAL", "Todo"}, null)) {
            if (calendar == null || !calendar.moveToFirst()) throw new IllegalArgumentException("Not local");
        }
        String key = (String) event.get("copy_key");
        if (key == null || !key.startsWith("todo-copy:")) throw new IllegalArgumentException("Missing key");
        ContentValues value = values(calendarId, event, false);
        return AgendaCopyOperation.apply(key, new AgendaCopyOperation.Store() {
            public String find(String copyKey) {
                try (Cursor cursor = resolver.query(Events.CONTENT_URI, new String[] {Events._ID},
                        Events.CALENDAR_ID + " = ? AND " + Events.CUSTOM_APP_URI + " = ? AND " + Events.DELETED + " = 0",
                        new String[] {calendarId, copyKey}, Events._ID + " ASC")) {
                    return cursor != null && cursor.moveToFirst() ? Long.toString(cursor.getLong(0)) : null;
                }
            }
            public void update(String id) {
                if (event.get("rrule") == null) { value.putNull(Events.RRULE); value.putNull(Events.DURATION); }
                else value.putNull(Events.DTEND);
                if (resolver.update(ContentUris.withAppendedId(Events.CONTENT_URI, Long.parseLong(id)), value, null, null) != 1)
                    throw new IllegalStateException("Copy disappeared");
            }
            public String insert() {
                Uri inserted = resolver.insert(Events.CONTENT_URI, value);
                if (inserted == null) throw new IllegalStateException("Copy failed");
                return Long.toString(ContentUris.parseId(inserted));
            }
        });
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
