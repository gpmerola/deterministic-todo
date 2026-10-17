package app.deterministic.todo.runtracker;

import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import androidx.work.WorkManager;

import java.io.File;
import java.security.KeyStore;
import java.util.List;
import java.util.Set;
import java.util.concurrent.Executors;

/**
 * Version 1 stops background work registered by the archived movement
 * features (GPS, Bip U, Health Connect audits, Drive diagnostics). Version 2,
 * at the user's request of 7 October 2026, deletes their data: preferences,
 * files, the Bip U key and (through RunDatabase.MIGRATION_5_6) the tables.
 * Step minutes and the daily goal stay. The code lives at tag
 * archive/movimento-completo-b189.
 */
public final class MovementArchiveCleanup {
    private static final String PREFS = "movement_archive_cleanup";
    private static final int VERSION = 2;
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

    /** Preferences written only by archived features. */
    static final List<String> ARCHIVED_PREFERENCES = List.of(
        "bip_u_private", "bip_u_auto_schedule", "bip_u_sync_debug",
        "diagnostic_upload_debug", "movement_activity_timeline",
        "movement_drive_export", "movement_intensive_experiment",
        "movement_intensive_status", "movement_intensive_store",
        "movement_intensive_upload_debug", "movement_live_state",
        "movement_passive_audit", "movement_passive_debug",
        "rolling_diagnostic_bundle");
    /** Per-source files named with this prefix plus a suffix. */
    static final String ARCHIVED_PREFERENCE_PREFIX = "passive_source_history_";
    /** Still read by the step counter: never deleted. */
    static final Set<String> KEPT_PREFERENCES = Set.of(
        "local_step_recording", "phone_daily_steps", "movement_profile", PREFS);
    static final String PROFILE = "movement_profile";
    static final String STEP_GOAL = "daily_step_goal";
    static final String BIP_U_KEY_ALIAS = "bip_u_auth_key_encryption";

    private MovementArchiveCleanup() {}

    public static void runOnce(Context context) {
        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        int done = prefs.getInt("version", 0);
        if (done >= VERSION) return;
        if (done < 1) stopArchivedWork(app);
        // Files, keystore and database work stay off the main thread.
        Executors.newSingleThreadExecutor().execute(() -> {
            deleteArchivedData(app);
            prefs.edit().putInt("version", VERSION).apply();
        });
    }

    private static void stopArchivedWork(Context app) {
        WorkManager work = WorkManager.getInstance(app);
        for (String tag : ARCHIVED_WORKERS) work.cancelAllWorkByTag(tag);
        // Cancelling the registered PendingIntent drops the activity-recognition
        // subscription without depending on Play Services location.
        Intent transitions = new Intent().setComponent(
            new ComponentName(app, ACTIVITY_TRANSITION_RECEIVER));
        PendingIntent registered = PendingIntent.getBroadcast(app, ACTIVITY_TRANSITION_REQUEST_CODE,
            transitions, PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_MUTABLE);
        if (registered != null) registered.cancel();
    }

    /** Best effort, each part independent; a later launch retries what failed. */
    static void deleteArchivedData(Context app) {
        for (String name : ARCHIVED_PREFERENCES) app.deleteSharedPreferences(name);
        File[] prefsFiles = new File(app.getDataDir(), "shared_prefs").listFiles();
        if (prefsFiles != null) {
            for (File file : prefsFiles) {
                String name = file.getName();
                if (name.startsWith(ARCHIVED_PREFERENCE_PREFIX) && name.endsWith(".xml"))
                    app.deleteSharedPreferences(name.substring(0, name.length() - 4));
            }
        }
        // Weight, strides and the rest of the old profile; the goal stays.
        SharedPreferences profile = app.getSharedPreferences(PROFILE, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = profile.edit();
        for (String key : profile.getAll().keySet()) if (!STEP_GOAL.equals(key)) editor.remove(key);
        editor.apply();
        deleteTree(new File(app.getFilesDir(), "movement_intensive"));
        deleteTree(new File(app.getCacheDir(), "runtracker"));
        try {
            KeyStore keys = KeyStore.getInstance("AndroidKeyStore");
            keys.load(null);
            if (keys.containsAlias(BIP_U_KEY_ALIAS)) keys.deleteEntry(BIP_U_KEY_ALIAS);
        } catch (Exception ignored) {
            // No key on this device, or the keystore is unavailable.
        }
        try {
            // Opening runs MIGRATION_5_6; VACUUM returns the freed pages.
            RunDatabase.get(app).getOpenHelper().getWritableDatabase().execSQL("VACUUM");
        } catch (RuntimeException ignored) {
            // Space is reclaimed on a later launch.
        }
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteTree(child);
        //noinspection ResultOfMethodCallIgnored
        file.delete();
    }
}
