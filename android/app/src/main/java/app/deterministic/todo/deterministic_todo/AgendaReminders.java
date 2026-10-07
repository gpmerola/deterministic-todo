package app.deterministic.todo.deterministic_todo;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentUris;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.CalendarContract;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Private, replaceable scheduling cache, not a calendar source of truth.
 * One OS alarm for the next batch; no polling, network, wake lock or service.
 */
final class AgendaReminders {
    static final String CHANNEL = "calendar_reminders";
    private static final String PREFS = "agenda_reminders";
    private static final String EVENTS = "events";
    private static final String SENT = "sent";
    private AgendaReminders() {}

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean enabled(Context context) {
        return prefs(context).getBoolean("enabled", true);
    }

    static boolean active(Context context) {
        return enabled(context) && prefs(context).getBoolean("accessible", false);
    }

    static Map<String, Object> status(Context context) {
        createChannel(context);
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        Map<String, Object> out = new HashMap<>();
        out.put("notifications", manager.areNotificationsEnabled()
            && manager.getNotificationChannel(CHANNEL).getImportance() != NotificationManager.IMPORTANCE_NONE);
        out.put("exact", exact(context));
        try { out.put("scheduled", new JSONArray(prefs(context).getString(EVENTS, "[]")).length()); }
        catch (Exception ignored) { out.put("scheduled", 0); }
        int posted = 0;
        for (android.service.notification.StatusBarNotification item : manager.getActiveNotifications())
            if (item.getTag() != null && item.getTag().startsWith("calendar:")) posted++;
        out.put("posted", posted);
        return out;
    }

    static boolean exact(Context context) {
        return Build.VERSION.SDK_INT < 31
            || context.getSystemService(AlarmManager.class).canScheduleExactAlarms();
    }

    private static void createChannel(Context context) {
        NotificationChannel channel = new NotificationChannel(CHANNEL,
            "Promemoria Calendario", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("Eventi del Calendario, 30 minuti prima");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    static synchronized long begin(Context context) {
        long generation = prefs(context).getLong("generation", 0) + 1;
        prefs(context).edit().putLong("generation", generation).commit();
        return generation;
    }

    static synchronized void replace(Context context, long generation, boolean on, boolean accessible,
                                     List<Map<String, Object>> events) throws Exception {
        SharedPreferences prefs = prefs(context);
        if (generation != prefs.getLong("generation", 0)) return;
        JSONArray previous = new JSONArray(prefs.getString(EVENTS, "[]"));
        java.util.Set<String> known = new java.util.HashSet<>();
        for (int i = 0; i < previous.length(); i++) known.add(previous.getJSONObject(i).getString("id"));
        JSONObject sent = new JSONObject(prefs.getString(SENT, "{}"));
        JSONObject keepSent = new JSONObject();
        JSONArray next = new JSONArray();
        long now = System.currentTimeMillis();
        if (on && accessible) for (Map<String, Object> row : events) {
            JSONObject event = new JSONObject(row);
            String id = event.getString("id");
            if (sent.has(id)) keepSent.put(id, true);
            if (!sent.has(id) && shouldKeep(event.getLong("at"), event.getLong("start"), now, known.contains(id))) {
                next.put(event);
            }
        }
        // Retain recently delivered IDs across refreshes, including when no
        // longer returned by the seven-day plan; bounded by the plan itself.
        prefs.edit().putBoolean("enabled", on).putBoolean("accessible", accessible).putString(EVENTS, next.toString())
            .putString(SENT, keepSent.toString()).commit();
        if (!on || !accessible) {
            NotificationManager notifications = context.getSystemService(NotificationManager.class);
            for (android.service.notification.StatusBarNotification posted : notifications.getActiveNotifications()) {
                if (posted.getTag() != null && posted.getTag().startsWith("calendar:"))
                    notifications.cancel(posted.getTag(), posted.getId());
            }
            AgendaReminderJob.cancel(context);
        } else AgendaReminderJob.schedule(context);
        arm(context);
    }

    static boolean shouldKeep(long at, long start, long now, boolean known) {
        return start > now && (at > now || known);
    }

    private static PendingIntent alarm(Context context) {
        return PendingIntent.getBroadcast(context, 7304,
            new Intent(context, AgendaReminderReceiver.class).setAction("calendar.remind"),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static synchronized void arm(Context context) throws Exception {
        AlarmManager manager = context.getSystemService(AlarmManager.class);
        PendingIntent intent = alarm(context);
        manager.cancel(intent);
        if (!enabled(context)) return;
        JSONArray events = new JSONArray(prefs(context).getString(EVENTS, "[]"));
        long at = Long.MAX_VALUE;
        for (int i = 0; i < events.length(); i++) at = Math.min(at, events.getJSONObject(i).getLong("at"));
        if (at == Long.MAX_VALUE) return;
        at = Math.max(System.currentTimeMillis() + 1000, at);
        try {
            if (exact(context)) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent);
            else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent);
        } catch (SecurityException revoked) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent);
        }
    }

    static synchronized void deliver(Context context) throws Exception {
        if (!enabled(context)) return;
        SharedPreferences prefs = prefs(context);
        JSONArray events = new JSONArray(prefs.getString(EVENTS, "[]"));
        JSONObject sent = new JSONObject(prefs.getString(SENT, "{}"));
        JSONArray remaining = new JSONArray();
        long now = System.currentTimeMillis();
        createChannel(context);
        for (int i = 0; i < events.length(); i++) {
            JSONObject event = events.getJSONObject(i);
            if (event.getLong("at") > now) { remaining.put(event); continue; }
            String id = event.getString("id");
            if (!sent.has(id) && event.getLong("start") > now && stillExists(context, event)) {
                // Persist before posting: retries/reboots cannot duplicate it.
                sent.put(id, true);
                prefs.edit().putString(SENT, sent.toString()).commit();
                post(context, event);
            }
        }
        prefs.edit().putString(EVENTS, remaining.toString()).commit();
        arm(context);
    }

    /** Last-second provider validation suppresses deleted/moved/declined events. */
    private static boolean stillExists(Context context, JSONObject event) throws Exception {
        if (context.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return false;
        long start = event.getLong("start");
        Uri.Builder uri = CalendarContract.Instances.CONTENT_URI.buildUpon();
        ContentUris.appendId(uri, start);
        ContentUris.appendId(uri, start + 1);
        try (Cursor cursor = context.getContentResolver().query(uri.build(),
            new String[] {CalendarContract.Instances.BEGIN, CalendarContract.Instances.TITLE},
            CalendarContract.Instances.EVENT_ID + " = ? AND "
                + CalendarContract.Instances.BEGIN + " = ? AND "
                + CalendarContract.Instances.STATUS + " != 2 AND "
                + CalendarContract.Instances.SELF_ATTENDEE_STATUS + " != 2",
            new String[] {event.getString("eventId"), Long.toString(start)}, null)) {
            if (cursor == null || !cursor.moveToFirst()) return false;
            event.put("title", cursor.getString(1));
            return true;
        }
    }

    private static void post(Context context, JSONObject event) throws Exception {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (!manager.areNotificationsEnabled()) return;
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open == null) return;
        open.setAction(context.getPackageName() + ".OPEN_CALENDAR");
        PendingIntent tap = PendingIntent.getActivity(context, 7304, open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        String time = android.text.format.DateFormat.getTimeFormat(context)
            .format(new java.util.Date(event.getLong("start")));
        Notification notification = new Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_calendar_notification)
            .setContentTitle(event.getString("title"))
            .setContentText("Inizia alle " + time)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(tap).setAutoCancel(true).build();
        manager.notify("calendar:" + event.getString("id"), 7304, notification);
    }
}
