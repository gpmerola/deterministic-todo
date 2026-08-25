package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import java.util.UUID;

/** One user action exports every diagnostic source already available on the phone. */
final class ManualDiagnosticExportScheduler {
    static final String MOVEMENT_WORK = "movement-manual-passive-export";
    static final String DIAGNOSTIC_WORK = "movement-manual-diagnostic-export";

    private ManualDiagnosticExportScheduler() {}

    static UUID enqueue(Context context) {
        Constraints connected = new Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED).build();
        OneTimeWorkRequest movement = new OneTimeWorkRequest.Builder(
            PassiveMovementAuditWorker.class)
            .setConstraints(connected)
            .setInputData(new Data.Builder().putBoolean(
                PassiveMovementAuditWorker.INPUT_MANUAL_EXPORT, true).build())
            .build();
        OneTimeWorkRequest unified = new OneTimeWorkRequest.Builder(
            DiagnosticDriveWorker.class)
            .setConstraints(connected)
            .setInputData(new Data.Builder().putBoolean(
                DiagnosticDriveWorker.INPUT_MANUAL_EXPORT, true).build())
            .build();
        WorkManager workManager = WorkManager.getInstance(context);
        // Keep the branches independent: a passive/Health Connect retry must not
        // prevent the raw diagnostic log and unified report from being uploaded.
        workManager.enqueueUniqueWork(MOVEMENT_WORK, ExistingWorkPolicy.REPLACE, movement);
        workManager.enqueueUniqueWork(DIAGNOSTIC_WORK, ExistingWorkPolicy.REPLACE, unified);
        return unified.getId();
    }
}
