package app.deterministic.todo.runtracker;

import android.content.Context;

public final class BipUAutomaticSyncScheduler {
    private BipUAutomaticSyncScheduler() {}

    public static void schedule(Context context) { BipUAutomaticSyncWorker.schedule(context); }
    public static void refreshIfDue(Context context) { BipUAutomaticSyncWorker.refreshIfDue(context); }
    public static boolean debugSyncNow(Context context) {
        new BipUAutomaticSyncClient(context, ignored -> {}).start();
        return true;
    }
}
