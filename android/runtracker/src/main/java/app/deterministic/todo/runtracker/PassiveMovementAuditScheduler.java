package app.deterministic.todo.runtracker;

import android.content.Context;

/** Keeps WorkManager implementation types private to the movement module. */
public final class PassiveMovementAuditScheduler {
    private PassiveMovementAuditScheduler() {}

    public static void refreshIfEnabled(Context context) {
        PassiveMovementAuditWorker.refreshScheduleIfEnabled(context);
    }
}
