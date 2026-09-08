package app.deterministic.todo.runtracker;

import android.content.Context;

/** Public facade that keeps WorkManager implementation types inside the module. */
public final class DiagnosticDriveScheduler {
    private DiagnosticDriveScheduler() {}

    public static void schedule(Context context) {
        DiagnosticDriveWorker.schedule(context);
    }
}
