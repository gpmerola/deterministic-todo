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

    public static void register(Context context, FlutterEngine engine) {
        Context app = context.getApplicationContext();
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/agenda")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("deviceZone")) {
                    result.success(deviceZone(ZoneId.systemDefault(), Instant.now()));
                    return;
                }
                if (!call.method.equals("instances")) {
                    result.notImplemented();
                    return;
                }
                Number start = call.argument("start");
                Number end = call.argument("end");
                List<String> calendarIds = call.argument("calendarIds");
                if (start == null || end == null || calendarIds == null) {
                    result.error("invalid_range", "Missing range", null);
                    return;
                }
                Handler main = new Handler(Looper.getMainLooper());
                IO.execute(() -> {
                    try {
                        List<Map<String, Object>> rows =
                            instances(app, start.longValue(), end.longValue(), calendarIds);
                        main.post(() -> result.success(rows));
                    } catch (SecurityException denied) {
                        main.post(() -> result.error("permission_denied", "Calendar access denied", null));
                    } catch (RuntimeException error) {
                        main.post(() -> result.error("query_failed", "Calendar query failed", null));
                    }
                });
            });
    }

    static List<Map<String, Object>> instances(Context context, long start, long end, List<String> calendarIds) {
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
        try (Cursor cursor = context.getContentResolver().query(uri.build(), PROJECTION,
                CalendarContract.Instances.CALENDAR_ID + " IN (" + placeholders + ")",
                calendarIds.toArray(new String[0]),
                CalendarContract.Instances.BEGIN + " ASC")) {
            if (cursor == null) return rows;
            while (cursor.moveToNext()) {
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
