package app.deterministic.todo.deterministic_todo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import java.util.List;
import java.util.Map;

/** Foreground-only alerts. The ledger contains opaque occurrence hashes and
 * expiry instants, never titles, descriptions, people or calendar accounts. */
final class AgendaUrgentVisits {
    static final String CHANNEL = "calendar_urgent_visits";
    private AgendaUrgentVisits() {}

    static synchronized int deliver(Context context, List<Map<String, Object>> events) throws Exception {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL,
            "Nuove visite urgenti", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("Visite urgenti nuove rilevate all'apertura di Todo");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        manager.createNotificationChannel(channel);
        if (!manager.areNotificationsEnabled()
            || manager.getNotificationChannel(CHANNEL).getImportance() == NotificationManager.IMPORTANCE_NONE) return 0;
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open == null) return 0;
        NotificationLedger ledger = new NotificationLedger(context, "agenda_urgent_visits");
        List<Map<String, Object>> fresh = ledger.fresh(events);
        if (!fresh.isEmpty()) {
            open.setAction(context.getPackageName() + ".OPEN_CALENDAR");
            PendingIntent tap = PendingIntent.getActivity(context, 7305, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            String title = fresh.size() == 1 ? "⚠ URGENTE: nuova visita"
                : "⚠ URGENTI: " + fresh.size() + " nuove visite";
            String text = "Apri il Calendario per controllare le visite urgenti aggiunte.";
            Notification notification = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_urgent_visit_notification)
                .setColor(Color.rgb(198, 40, 40))
                .setContentTitle(title).setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setCategory(Notification.CATEGORY_EVENT)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setContentIntent(tap).setAutoCancel(true).build();
            // Stable tag replaces any previous summary. Permission failures do
            // not consume the ledger; opening again can retry after permission.
            manager.notify("calendar-urgent", 7305, notification);
        }
        ledger.commit();
        return fresh.size();
    }
}
