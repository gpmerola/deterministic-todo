package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.OutOfQuotaPolicy;
import androidx.work.WorkManager;
import androidx.work.BackoffPolicy;

import java.util.UUID;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.TimeUnit;

/** One user action exports every diagnostic source already available on the phone. */
final class ManualDiagnosticExportScheduler {
    static final String MOVEMENT_WORK = "movement-manual-passive-export";
    static final String DIAGNOSTIC_WORK = "movement-manual-diagnostic-export";
    static final String INTENSIVE_WORK = "movement-manual-intensive-upload";
    static final long INTENSIVE_DELAY_MINUTES = 2;

    private ManualDiagnosticExportScheduler() {}

    static UUID enqueue(Context context) {
        String manualBucket = LocalDateTime.now().format(
            DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss"));
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
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .setInputData(new Data.Builder()
                .putBoolean(DiagnosticDriveWorker.INPUT_MANUAL_EXPORT, true)
                .putString(DiagnosticDriveWorker.INPUT_MANUAL_BUCKET, manualBucket)
                .build())
            .build();
        OneTimeWorkRequest intensive = new OneTimeWorkRequest.Builder(
            IntensiveDiagnosticUploadWorker.class)
            .setConstraints(connected)
            .setInitialDelay(INTENSIVE_DELAY_MINUTES, TimeUnit.MINUTES)
            .setBackoffCriteria(BackoffPolicy.LINEAR,
                OneTimeWorkRequest.MIN_BACKOFF_MILLIS, TimeUnit.MILLISECONDS)
            .build();
        WorkManager workManager = WorkManager.getInstance(context);
        // A single durable chain owns the essential package. WorkManager resumes
        // it even if Android suspends the UI process between individual files.
        workManager.beginUniqueWork(DIAGNOSTIC_WORK, ExistingWorkPolicy.REPLACE, unified)
            .then(movement)
            .enqueue();
        workManager.enqueueUniqueWork(INTENSIVE_WORK, ExistingWorkPolicy.REPLACE, intensive);
        return unified.getId();
    }
}
