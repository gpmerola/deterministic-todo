package app.deterministic.todo.deterministic_todo;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

/** Restores local alarms after reboot/update/time changes, without cloud. */
public final class AgendaReminderReceiver extends BroadcastReceiver {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    @Override public void onReceive(Context context, Intent intent) {
        PendingResult pending = goAsync();
        IO.execute(() -> {
            try {
                if ("calendar.remind".equals(intent.getAction())) AgendaReminders.deliver(context);
                else if (AgendaReminders.active(context)) {
                    AgendaReminders.arm(context);
                    AgendaReminderJob.refreshSoon(context);
                }
            } catch (Exception ignored) {
                // No titles, identifiers or calendar data in diagnostics.
                AgendaReminderJob.refreshSoon(context);
            } finally { pending.finish(); }
        });
    }
}
