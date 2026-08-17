package app.deterministic.todo.runtracker;

import android.content.Context;

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
    private static final String WORK = "movement-passive-audit";
    private static final String STARTUP_WORK = "movement-passive-audit-startup";
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

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        if (!enabled(context)) {
            disable(context);
            return Result.success();
        }
        ZoneId zone = ZoneId.systemDefault();
        LocalDateTime now = LocalDateTime.now(zone);
        AuditRead current = readAudit(context, now.toLocalDate());
        if (current.audit == null) return resultFor(current.error);
        DriveTestExportManager.ExportResult snapshot =
            DriveTestExportManager.writePassiveSnapshot(context, current.audit, now);
        if (!snapshot.success()) return Result.retry();

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

    private static Result resultFor(String error) {
        return "permission_required".equals(error) ? Result.failure() : Result.retry();
    }
}
