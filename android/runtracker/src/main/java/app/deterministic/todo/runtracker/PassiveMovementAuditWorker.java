package app.deterministic.todo.runtracker;

import android.content.Context;
import android.os.SystemClock;

import androidx.annotation.NonNull;
import androidx.work.Constraints;
import androidx.work.ExistingWorkPolicy;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class PassiveMovementAuditWorker extends Worker {
    static final String INPUT_MANUAL_EXPORT = "manual_export";
    private static final String WORK = "movement-passive-audit";
    private static final String STARTUP_WORK = "movement-passive-audit-startup";
    private static final String FINAL_INTENSIVE_UPLOAD = "movement-intensive-final-upload";
    private static final String PREFS = "movement_passive_audit";
    private static final String END_AT = "end_at";
    private static final String LAST_FINAL_DAY = "last_final_day";
    static final long PERIODIC_INTERVAL_HOURS = 1;

    public PassiveMovementAuditWorker(@NonNull Context context, @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    static boolean enabled(Context context) {
        return PassiveAuditWindow.active(System.currentTimeMillis(),
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(END_AT, 0));
    }

    static long endAt(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(END_AT, 0);
    }

    static void enable(Context context) {
        long end = PassiveAuditWindow.endAt(System.currentTimeMillis());
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(END_AT, end).apply();
        schedule(context, true);
    }

    static void ensureEnabledUntil(Context context, long requiredEndAt) {
        long existing = endAt(context);
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(END_AT, Math.max(existing, requiredEndAt)).apply();
        schedule(context, true);
    }

    public static void refreshScheduleIfEnabled(Context context) {
        if (enabled(context)) schedule(context, true);
    }

    private static void schedule(Context context, boolean includeStartup) {
        Constraints connected = new Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED).build();
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
            PassiveMovementAuditWorker.class, PERIODIC_INTERVAL_HOURS, TimeUnit.HOURS)
            .setConstraints(connected).build();
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK, ExistingPeriodicWorkPolicy.UPDATE, request);
        if (includeStartup) {
            OneTimeWorkRequest startup = new OneTimeWorkRequest.Builder(
                PassiveMovementAuditWorker.class)
                .setConstraints(connected)
                .setInitialDelay(1, TimeUnit.MINUTES).build();
            WorkManager.getInstance(context).enqueueUniqueWork(
                STARTUP_WORK, ExistingWorkPolicy.REPLACE, startup);
        }
    }

    static void disable(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(END_AT).apply();
        WorkManager.getInstance(context).cancelUniqueWork(WORK);
        WorkManager.getInstance(context).cancelUniqueWork(STARTUP_WORK);
    }

    static void scheduleIntensiveUpload(Context context) {
        Constraints connected = new Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED).build();
        OneTimeWorkRequest upload = new OneTimeWorkRequest.Builder(
            IntensiveDiagnosticUploadWorker.class).setConstraints(connected)
            .setBackoffCriteria(androidx.work.BackoffPolicy.LINEAR,
                OneTimeWorkRequest.MIN_BACKOFF_MILLIS, TimeUnit.MILLISECONDS).build();
        WorkManager.getInstance(context).enqueueUniqueWork(
            FINAL_INTENSIVE_UPLOAD, ExistingWorkPolicy.REPLACE, upload);
    }

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        boolean manualExport = getInputData().getBoolean(INPUT_MANUAL_EXPORT, false);
        if (!enabled(context) && !manualExport) {
            disable(context);
            return Result.success();
        }
        PassiveMovementDebugState.started(context, DriveTestExportManager.isConfigured(context));
        ZoneId zone = ZoneId.systemDefault();
        LocalDateTime now = LocalDateTime.now(zone);
        AuditRead current = readAudit(context, now.toLocalDate());
        if (current.audit == null) {
            PassiveMovementDebugState.healthError(context, current.error);
            return resultFor(current.error);
        }
        long exportStarted = SystemClock.elapsedRealtime();
        DriveTestExportManager.ExportResult snapshot = manualExport
            ? DriveTestExportManager.writeManualPassiveSnapshot(context, current.audit, now)
            : DriveTestExportManager.writePassiveSnapshot(context, current.audit, now);
        long exportDuration = SystemClock.elapsedRealtime() - exportStarted;
        PassiveMovementDebugState.exportFinished(context, current.audit, now, snapshot,
            exportDuration);
        if (!snapshot.success()) return Result.retry();
        if (manualExport) return Result.success();

        LocalDate finalDay = PassiveAuditWindow.completedDay(now.toLocalDate(), now.getHour());
        String lastFinal = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(LAST_FINAL_DAY, "");
        if (finalDay.toString().equals(lastFinal)) return Result.success();
        AuditRead completed = readAudit(context, finalDay);
        if (completed.audit == null) return resultFor(completed.error);
        DriveTestExportManager.ExportResult result =
            DriveTestExportManager.writePassiveAudit(context, completed.audit);
        if (result.success()) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_FINAL_DAY, finalDay.toString()).apply();
            return Result.success();
        }
        return Result.retry();
    }

    private record AuditRead(HealthConnectGateway.PassiveAudit audit, String error) {}

    private static AuditRead readAudit(Context context, LocalDate day) {
        if (day.equals(LocalDate.now(ZoneId.systemDefault()))) refreshLocalCounter(context);
        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<HealthConnectGateway.PassiveAudit> audit = new AtomicReference<>();
        AtomicReference<String> error = new AtomicReference<>();
        HealthConnectGateway.auditDay(context, day, new HealthConnectGateway.AuditCallback() {
            @Override public void onSuccess(HealthConnectGateway.PassiveAudit value) {
                audit.set(value); latch.countDown();
            }
            @Override public void onError(String code) { error.set(code); latch.countDown(); }
        });
        try {
            if (!latch.await(30, TimeUnit.SECONDS)) return new AuditRead(null, "timeout");
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return new AuditRead(null, "interrupted");
        }
        return new AuditRead(audit.get(), error.get());
    }

    private static void refreshLocalCounter(Context context) {
        CountDownLatch latch = new CountDownLatch(1);
        PhoneDailyMovementGateway.refreshToday(context, new PhoneDailyMovementGateway.Callback() {
            @Override public void onSuccess(DailyMovement movement, long phoneSteps,
                                            long bipSteps, String fusionSource) {
                latch.countDown();
            }
            @Override public void onPermissionRequired() { latch.countDown(); }
            @Override public void onUnavailable() { latch.countDown(); }
            @Override public void onError() { latch.countDown(); }
        });
        try {
            latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    private static Result resultFor(String error) {
        return "permission_required".equals(error) ? Result.failure() : Result.retry();
    }

}
