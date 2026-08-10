package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.BackoffPolicy;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class MovementComparisonWorker extends Worker {
    private static final String SESSION_ID = "session_id";

    public MovementComparisonWorker(@NonNull Context context, @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    static void schedule(Context context, long sessionId) {
        DriveTestExportManager.captureComparisonAttempt(context, sessionId, "scheduled", 0);
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(MovementComparisonWorker.class)
            .setInputData(new Data.Builder().putLong(SESSION_ID, sessionId).build())
            .setInitialDelay(15, TimeUnit.SECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .build();
        WorkManager.getInstance(context).enqueueUniqueWork(
            "movement-fit-" + sessionId, ExistingWorkPolicy.REPLACE, request);
    }

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        long id = getInputData().getLong(SESSION_ID, 0);
        RunDao dao = RunDatabase.get(context).runs();
        RunSession session = dao.session(id);
        if (session == null || session.endedAtMillis == null) return Result.failure();
        DriveTestExportManager.captureComparisonAttempt(context, id, "waiting", getRunAttemptCount() + 1);

        CountDownLatch comparisonLatch = new CountDownLatch(1);
        AtomicReference<HealthConnectGateway.GoogleFitComparison> comparison = new AtomicReference<>();
        AtomicReference<String> error = new AtomicReference<>();
        HealthConnectGateway.compareGoogleFit(context, session, new HealthConnectGateway.ComparisonCallback() {
            @Override public void onSuccess(HealthConnectGateway.GoogleFitComparison value) {
                comparison.set(value); comparisonLatch.countDown();
            }
            @Override public void onPermissionRequired() { error.set("permission_required"); comparisonLatch.countDown(); }
            @Override public void onUnavailable() { error.set("unavailable"); comparisonLatch.countDown(); }
            @Override public void onError() { error.set("health_error"); comparisonLatch.countDown(); }
        });
        try {
            if (!comparisonLatch.await(20, TimeUnit.SECONDS)) error.set("timeout");
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt(); return Result.retry();
        }

        HealthConnectGateway.GoogleFitComparison value = comparison.get();
        if (value == null || (value.getSteps() == null && value.getDistanceMeters() == null)) {
            String status = error.get() == null ? "fit_not_synced" : error.get();
            DriveTestExportManager.captureComparisonAttempt(context, id, status, getRunAttemptCount() + 1);
            boolean permissionFailure = "permission_required".equals(status);
            boolean retry = !permissionFailure &&
                MovementComparisonRetryPolicy.retryMissingReference(getRunAttemptCount());
            if (!retry) exportDiagnosticState(context, session, dao);
            return retry ? Result.retry() : Result.failure();
        }

        DriveTestExportManager.captureGoogleFitComparison(context, id, value);
        CountDownLatch exportLatch = new CountDownLatch(1);
        AtomicReference<DriveTestExportManager.ExportResult> export = new AtomicReference<>();
        DriveTestExportManager.finish(context, session, dao.points(id), result -> {
            export.set(result); exportLatch.countDown();
        });
        try {
            if (!exportLatch.await(20, TimeUnit.SECONDS)) {
                DriveTestExportManager.setComparisonStatus(context, "drive_timeout");
                return Result.retry();
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt(); return Result.retry();
        }
        if (export.get() == null || !export.get().success()) {
            DriveTestExportManager.setComparisonStatus(context, "drive_failed");
            return Result.retry();
        }
        DriveTestExportManager.captureComparisonAttempt(context, id, "success", getRunAttemptCount() + 1);
        return MovementComparisonRetryPolicy.refreshAvailableReference(getRunAttemptCount())
            ? Result.retry() : Result.success();
    }

    private static void exportDiagnosticState(Context context, RunSession session, RunDao dao) {
        CountDownLatch latch = new CountDownLatch(1);
        DriveTestExportManager.finish(context, session, dao.points(session.id), result -> latch.countDown());
        try { latch.await(20, TimeUnit.SECONDS); }
        catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
    }
}
