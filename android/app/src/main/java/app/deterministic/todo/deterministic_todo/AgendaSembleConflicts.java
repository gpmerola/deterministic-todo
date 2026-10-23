package app.deterministic.todo.deterministic_todo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import java.text.SimpleDateFormat;
import java.util.Date;
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
        NotificationLedger ledger = new NotificationLedger(context, "agenda_semble_conflicts");
        List<Map<String, Object>> fresh = ledger.fresh(events);
        if (!fresh.isEmpty()) {
            long first = Long.MAX_VALUE;
            for (Map<String, Object> event : fresh) {
                first = Math.min(first, ((Number) event.get("start")).longValue());
            }
            // The tap opens that event (or the day of the first one) in the
            // Calendar: the start instant is the only data in the intent.
            open.setAction(context.getPackageName() + ".OPEN_CALENDAR")
                .putExtra(CalendarLaunchRequest.EXTRA_EVENT_START, first)
                .putExtra(CalendarLaunchRequest.EXTRA_SINGLE, fresh.size() == 1);
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
                    + ". Tocca per aprirlo e bloccarlo in Semble.";
            } else {
                title = fresh.size() + " eventi in orario Semble prenotabile";
                text = "Tocca per aprire il giorno del primo: hanno il bordo ambra e si bloccano in Semble con un tocco.";
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
        ledger.commit();
        return fresh.size();
    }
}
