package app.deterministic.todo.deterministic_todo;

import android.content.ContentUris;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.CalendarContract;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * One Instances query per range for the Agenda. The calendar plugin runs two
 * extra queries per event (attendees, reminders) and ships whole HTML invite
 * bodies; the Agenda needs neither. Descriptions are reduced to meeting URLs
 * here and never logged.
 */
public final class AgendaChannel {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Pattern URL = Pattern.compile("https://[^\\s<>\"]+");
    private static final String[] PROJECTION = {
        CalendarContract.Instances.EVENT_ID,
        CalendarContract.Instances.CALENDAR_ID,
        CalendarContract.Instances.TITLE,
        CalendarContract.Instances.EVENT_LOCATION,
        CalendarContract.Instances.DESCRIPTION,
        CalendarContract.Instances.BEGIN,
        CalendarContract.Instances.END,
        CalendarContract.Instances.ALL_DAY,
        CalendarContract.Instances.STATUS,
        CalendarContract.Instances.RRULE,
        CalendarContract.Instances.SELF_ATTENDEE_STATUS,
        CalendarContract.Instances.EVENT_TIMEZONE,
        CalendarContract.Instances.IS_ORGANIZER,
    };

    private AgendaChannel() {}

    /** The visible app's engine: also receives background runs. */
    public static void register(Context context, FlutterEngine engine) {
        registerHandlers(context.getApplicationContext(), engine);
        AgendaBackground.attachAppEngine(engine);
    }

    static void registerHandlers(Context context, FlutterEngine engine) {
        Context app = context.getApplicationContext();
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/agenda")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("timeZones")) {
                    List<String> zones = new ArrayList<>(ZoneId.getAvailableZoneIds());
                    java.util.Collections.sort(zones);
                    result.success(zones);
                    return;
                }
                if (call.method.equals("resolveZone")) {
                    try {
                        result.success(AgendaTimeZones.resolve(call.argument("zone"), call.argument("start"),
                            call.argument("end"), call.argument("until")));
                    } catch (RuntimeException error) {
                        result.error("invalid_local_time", "Orario inesistente o ambiguo nel fuso scelto: scegli un altro orario.", null);
                    }
                    return;
                }
                if (call.method.equals("deviceZone")) {
                    result.success(deviceZone(ZoneId.systemDefault(), Instant.now()));
                    return;
                }
                if (call.method.equals("scheduleBackground")) {
                    AgendaBackground.schedule(app);
                    result.success(null);
                    return;
                }
                if (call.method.equals("cancelBackground")) {
                    AgendaBackground.cancel(app);
                    result.success(null);
                    return;
                }
                if (call.method.equals("localEvents") || call.method.equals("restoreLocalEvents") || call.method.equals("copyLocalEvent")) {
                    localEvents(app, call, result);
                    return;
                }
                if (!call.method.equals("instances")) {
                    result.notImplemented();
                    return;
                }
                Number start = call.argument("start");
                Number end = call.argument("end");
                List<String> calendarIds = call.argument("calendarIds");
                String titleQuery = call.argument("titleQuery");
                if (start == null || end == null || calendarIds == null) {
                    result.error("invalid_range", "Missing range", null);
                    return;
                }
                Handler main = new Handler(Looper.getMainLooper());
                IO.execute(() -> {
                    try {
                        List<Map<String, Object>> rows =
                            instances(app, start.longValue(), end.longValue(), calendarIds, titleQuery);
                        main.post(() -> result.success(rows));
                    } catch (SecurityException denied) {
                        main.post(() -> result.error("permission_denied", "Calendar access denied", null));
                    } catch (RuntimeException error) {
                        main.post(() -> result.error("query_failed", "Calendar query failed", null));
                    }
                });
            });
    }

    /** Backup and restore of Todo's own calendar, off the main thread. */
    private static void localEvents(Context app, io.flutter.plugin.common.MethodCall call,
                                    MethodChannel.Result result) {
        String calendarId = call.argument("calendarId");
        List<Map<String, Object>> events = call.argument("events");
        boolean restore = call.method.equals("restoreLocalEvents");
        if (calendarId == null || (restore && events == null)) {
            result.error("invalid_arguments", "Missing calendar", null);
            return;
        }
        Handler main = new Handler(Looper.getMainLooper());
        IO.execute(() -> {
            try {
                Object value = call.method.equals("copyLocalEvent")
                    ? AgendaLocalEvents.copy(app, calendarId, call.argument("event"))
                    : restore
                    ? AgendaLocalEvents.restore(app, calendarId, events)
                    : AgendaLocalEvents.read(app, calendarId);
                main.post(() -> result.success(value));
            } catch (SecurityException denied) {
                main.post(() -> result.error("permission_denied", "Calendar access denied", null));
            } catch (RuntimeException error) {
                main.post(() -> result.error("query_failed", "Calendar operation failed", null));
            }
        });
    }

    /** Title search keeps at most this many rows; Dart orders and trims. */
    static final int MAX_SEARCH_ROWS = 200;

    static List<Map<String, Object>> instances(Context context, long start, long end,
                                               List<String> calendarIds, String titleQuery) {
        List<Map<String, Object>> rows = new ArrayList<>();
        if (calendarIds.isEmpty() || end <= start) return rows;
        ZoneId zone = ZoneId.systemDefault();
        // All-day instances are stored at UTC midnights: widen so a local-day
        // window still matches them; Dart filters by civil day afterwards.
        long queryStart = Math.min(start, utcMidnightOfLocalDay(start, zone));
        long queryEnd = Math.max(end, utcMidnightOfLocalDay(end, zone));
        Uri.Builder uri = CalendarContract.Instances.CONTENT_URI.buildUpon();
        ContentUris.appendId(uri, queryStart);
        ContentUris.appendId(uri, queryEnd);
        String placeholders = String.join(",", java.util.Collections.nCopies(calendarIds.size(), "?"));
        String selection = CalendarContract.Instances.CALENDAR_ID + " IN (" + placeholders + ")";
        List<String> args = new ArrayList<>(calendarIds);
        // Title search is matched here, not with SQL LIKE: the provider's
        // LIKE folds ASCII case only, and "attivita" must find "attività".
        String needle = titleQuery == null ? "" : fold(titleQuery.trim());
        boolean search = !needle.isEmpty();
        if (search) {
            // Cheap superset in SQL (letters that may carry an accent match
            // any one character), confirmed below on the folded title.
            selection += " AND " + CalendarContract.Instances.TITLE + " LIKE ? ESCAPE '\\'";
            args.add("%" + likePrefilter(needle) + "%");
        }
        try (Cursor cursor = context.getContentResolver().query(uri.build(), PROJECTION,
                selection, args.toArray(new String[0]),
                CalendarContract.Instances.BEGIN + " ASC")) {
            if (cursor == null) return rows;
            while (cursor.moveToNext() && (!search || rows.size() < MAX_SEARCH_ROWS)) {
                if (search && (cursor.isNull(2) || !fold(cursor.getString(2)).contains(needle))) continue;
                long eventId = cursor.getLong(0);
                long begin = cursor.getLong(5);
                long finish = cursor.isNull(6) ? begin : cursor.getLong(6);
                boolean allDay = !cursor.isNull(7) && cursor.getInt(7) == 1;
                boolean recurring = !cursor.isNull(9);
                Map<String, Object> row = new HashMap<>();
                // Same id format as the plugin, so showEventModal opens it.
                row.put("instanceId", recurring ? eventId + "@" + begin : String.valueOf(eventId));
                row.put("calendarId", cursor.getString(1));
                row.put("title", cursor.isNull(2) ? "" : cursor.getString(2));
                row.put("location", cursor.getString(3));
                row.put("links", links(cursor.getString(4)));
                row.put("start", allDay ? localMidnightOfUtcDay(begin, zone) : begin);
                row.put("end", allDay ? localMidnightOfUtcDay(finish, zone) : finish);
                row.put("allDay", allDay);
                row.put("canceled", !cursor.isNull(8)
                    && cursor.getInt(8) == CalendarContract.Events.STATUS_CANCELED);
                // Invited and never answered: Outlook's dashed events.
                row.put("unanswered", !cursor.isNull(10)
                    && cursor.getInt(10) == CalendarContract.Attendees.ATTENDEE_STATUS_INVITED);
                // Accepted, declined or tentative. Exchange ActiveSync copies
                // often report "none" (0): unknown, not unanswered.
                row.put("answered", answered(cursor.isNull(10) ? -1 : cursor.getInt(10)));
                String eventZone = cursor.getString(11);
                row.put("timeZone", eventZone);
                // Unknown counts as organizer: local events have no attendees.
                row.put("organizer", cursor.isNull(12) || cursor.getInt(12) == 1);
                if (!allDay) row.put("eventZoneTimes", eventZoneTimes(begin, finish, eventZone, zone));
                rows.add(row);
            }
        }
        return rows;
    }

    static boolean answered(int status) {
        return status == CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED
            || status == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED
            || status == CalendarContract.Attendees.ATTENDEE_STATUS_TENTATIVE;
    }

    /** IANA id and current UTC offset, shown in the Agenda at all times. */
    static Map<String, Object> deviceZone(ZoneId zone, Instant now) {
        Map<String, Object> value = new HashMap<>();
        value.put("id", zone.getId());
        value.put("offsetSeconds", zone.getRules().getOffset(now).getTotalSeconds());
        return value;
    }

    /**
     * "13:00–14:00" in the event's own zone when it differs in offset from the
     * device; null otherwise or when the zone id is not a valid IANA name.
     */
    static String eventZoneTimes(long begin, long end, String eventZone, ZoneId device) {
        if (eventZone == null || eventZone.isEmpty()) return null;
        ZoneId zone;
        try {
            zone = ZoneId.of(eventZone);
        } catch (RuntimeException invalid) {
            return null;
        }
        Instant start = Instant.ofEpochMilli(begin);
        if (zone.getRules().getOffset(start).equals(device.getRules().getOffset(start))) return null;
        java.time.format.DateTimeFormatter clock = java.time.format.DateTimeFormatter.ofPattern("HH:mm");
        return clock.format(start.atZone(zone)) + "–" + clock.format(Instant.ofEpochMilli(end).atZone(zone));
    }

    /**
     * LIKE pattern for a folded needle: letters that have accented forms
     * become `_` (one character), wildcards in the text stay literal.
     */
    static String likePrefilter(String needle) {
        StringBuilder out = new StringBuilder();
        for (char c : needle.toCharArray()) {
            if ("aeiouycn".indexOf(c) >= 0) out.append('_');
            else if (c == '%' || c == '_' || c == '\\') out.append('\\').append(c);
            else out.append(c);
        }
        return out.toString();
    }

    /** Lower case without accents, for title search. */
    static String fold(String text) {
        return java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD)
            .replaceAll("\\p{M}", "")
            .toLowerCase(java.util.Locale.ROOT);
    }

    /** Only URLs, so invite bodies never cross the channel. */
    static String links(String description) {
        if (description == null || description.isEmpty()) return null;
        StringBuilder out = new StringBuilder();
        Matcher matcher = URL.matcher(description);
        while (matcher.find()) {
            String url = matcher.group();
            if (url.contains("teams.microsoft.com") || url.contains("teams.live.com")
                    || url.contains("zoom.us/") || url.contains("meet.google.com")) {
                if (out.length() > 0) out.append('\n');
                out.append(url);
            }
        }
        return out.length() == 0 ? null : out.toString();
    }

    static long utcMidnightOfLocalDay(long millis, ZoneId zone) {
        LocalDate day = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate();
        return day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli();
    }

    static long localMidnightOfUtcDay(long millis, ZoneId zone) {
        LocalDate day = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate();
        return day.atStartOfDay(zone).toInstant().toEpochMilli();
    }
}
