package app.deterministic.todo.runtracker;

import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import androidx.work.WorkManager;

import java.util.List;

/**
 * Stops background work registered by the archived movement features (GPS,
 * Bip U, Health Connect audits, Drive diagnostics) on devices that ran them.
 * Stored data is kept; the full code lives at tag archive/movimento-completo-b189.
 */
public final class MovementArchiveCleanup {
    private static final String PREFS = "movement_archive_cleanup";
    private static final int VERSION = 1;
    private static final String PACKAGE = "app.deterministic.todo.runtracker.";

    /** WorkManager tags every request with its worker class name. */
    static final List<String> ARCHIVED_WORKERS = List.of(
        PACKAGE + "BipUAutomaticSyncWorker",
        PACKAGE + "DiagnosticDriveWorker",
        PACKAGE + "IntensiveDiagnosticUploadWorker",
        PACKAGE + "MovementComparisonWorker",
        PACKAGE + "PassiveMovementAuditWorker");
    static final String ACTIVITY_TRANSITION_RECEIVER = PACKAGE + "ActivityTransitionReceiver";
    static final int ACTIVITY_TRANSITION_REQUEST_CODE = 8017;

    private MovementArchiveCleanup() {}

    public static void runOnce(Context context) {
        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (prefs.getInt("version", 0) >= VERSION) return;
        WorkManager work = WorkManager.getInstance(app);
        for (String tag : ARCHIVED_WORKERS) work.cancelAllWorkByTag(tag);
        // Cancelling the registered PendingIntent drops the activity-recognition
        // subscription without depending on Play Services location.
        Intent transitions = new Intent().setComponent(
            new ComponentName(app, ACTIVITY_TRANSITION_RECEIVER));
        PendingIntent registered = PendingIntent.getBroadcast(app, ACTIVITY_TRANSITION_REQUEST_CODE,
            transitions, PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_MUTABLE);
        if (registered != null) registered.cancel();
        prefs.edit().putInt("version", VERSION).apply();
    }
}
