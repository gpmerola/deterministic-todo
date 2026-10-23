package app.deterministic.todo.deterministic_todo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import org.json.JSONObject;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Events that arrived in bookable Semble time (build 304). The ledger holds
 * opaque occurrence hashes and expiry instants; the notification shows day
 * and time only, never titles, people or calendar accounts. */
final class AgendaSembleConflicts {
    static final String CHANNEL = "calendar_semble_conflicts";
    private AgendaSembleConflicts() {}

    static synchronized int deliver(Context context, List<Map<String, Object>> events) throws Exception {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL,
            "Eventi in orario Semble", NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription("Eventi arrivati in un orario prenotabile di Semble");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        manager.createNotificationChannel(channel);
        if (!manager.areNotificationsEnabled()
            || manager.getNotificationChannel(CHANNEL).getImportance() == NotificationManager.IMPORTANCE_NONE) return 0;
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open == null) return 0;
        long now = System.currentTimeMillis();
        SharedPreferences prefs = context.getSharedPreferences("agenda_semble_conflicts", Context.MODE_PRIVATE);
        JSONObject stored = new JSONObject(prefs.getString("sent", "{}"));
        JSONObject sent = new JSONObject();
        for (Iterator<String> keys = stored.keys(); keys.hasNext();) {
            String id = keys.next();
            if (stored.getLong(id) > now) sent.put(id, stored.getLong(id));
        }
        List<Map<String, Object>> fresh = new ArrayList<>();
        for (Map<String, Object> event : events) {
            String id = (String) event.get("id");
            long end = ((Number) event.get("end")).longValue();
            if (end <= now || sent.has(id)) continue;
            fresh.add(event);
            sent.put(id, end);
        }
        if (!fresh.isEmpty()) {
            open.setAction(context.getPackageName() + ".OPEN_CALENDAR");
            PendingIntent tap = PendingIntent.getActivity(context, 7306, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            String title;
            String text;
            if (fresh.size() == 1) {
                long start = ((Number) fresh.get(0).get("start")).longValue();
                long end = ((Number) fresh.get(0).get("end")).longValue();
                SimpleDateFormat day = new SimpleDateFormat("EEE d MMM, HH:mm", Locale.ITALIAN);
                SimpleDateFormat hour = new SimpleDateFormat("HH:mm", Locale.ITALIAN);
                title = "Evento in orario Semble prenotabile";
                text = day.format(new Date(start)) + "–" + hour.format(new Date(end))
                    + ". Tocca l'evento con il bordo ambra e poi «Blocca in Semble».";
            } else {
                title = fresh.size() + " eventi in orario Semble prenotabile";
                text = "Apri il Calendario: hanno il bordo ambra e si bloccano in Semble con un tocco.";
            }
            Notification notification = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_calendar_notification)
                .setColor(Color.rgb(208, 138, 0))
                .setContentTitle(title).setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setCategory(Notification.CATEGORY_EVENT)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setContentIntent(tap).setAutoCancel(true).build();
            // Stable tag: a newer summary replaces the previous one.
            manager.notify("calendar-semble-conflicts", 7306, notification);
        }
        if (!prefs.edit().putString("sent", sent.toString()).commit()) {
            throw new IllegalStateException("Semble conflict ledger unavailable");
        }
        return fresh.size();
    }
}
