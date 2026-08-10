package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.ExistingPeriodicWorkPolicy;
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
    private static final String PREFS = "movement_passive_audit";
    private static final String END_AT = "end_at";

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
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
            PassiveMovementAuditWorker.class, 6, TimeUnit.HOURS)
            .setInitialDelay(1, TimeUnit.MINUTES).build();
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK, ExistingPeriodicWorkPolicy.UPDATE, request);
    }

    static void disable(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(END_AT).apply();
        WorkManager.getInstance(context).cancelUniqueWork(WORK);
    }

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        if (!enabled(context)) {
            disable(context);
            return Result.success();
        }
        ZoneId zone = ZoneId.systemDefault();
        LocalDateTime now = LocalDateTime.now(zone);
        LocalDate day = PassiveAuditWindow.completedDay(now.toLocalDate(), now.getHour());
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
            if (!latch.await(30, TimeUnit.SECONDS)) return Result.retry();
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return Result.retry();
        }
        if (audit.get() == null) return "permission_required".equals(error.get())
            ? Result.failure() : Result.retry();
        DriveTestExportManager.ExportResult result =
            DriveTestExportManager.writePassiveAudit(context, audit.get());
        return result.success() ? Result.success() : Result.retry();
    }
}
