package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class BipUAutomaticSyncWorker extends Worker {
    static final long PERIOD_HOURS = 3;
    static final long FOREGROUND_MIN_INTERVAL_MS = 15L * 60 * 1000;
    private static final String WORK = "bip-u-automatic-history-sync";
    private static final String PREFS = "bip_u_auto_schedule";

    public BipUAutomaticSyncWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    static void schedule(Context context) {
        Constraints constraints = new Constraints.Builder().setRequiresBatteryNotLow(true).build();
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
            BipUAutomaticSyncWorker.class, PERIOD_HOURS, TimeUnit.HOURS)
            .setConstraints(constraints).build();
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK, ExistingPeriodicWorkPolicy.UPDATE, request);
    }

    static void refreshIfDue(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        synchronized (BipUAutomaticSyncWorker.class) {
            if (now - prefs.getLong("last_foreground_attempt_ms", 0) < FOREGROUND_MIN_INTERVAL_MS)
                return;
            prefs.edit().putLong("last_foreground_attempt_ms", now).apply();
        }
        new BipUAutomaticSyncClient(context, ignored -> {}).start();
    }

    @NonNull @Override public Result doWork() {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<String> outcome = new AtomicReference<>("automatic_timeout");
        new BipUAutomaticSyncClient(getApplicationContext(), value -> {
            outcome.set(value); done.countDown();
        }).start();
        try {
            if (!done.await(100, TimeUnit.SECONDS)) return Result.success();
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return Result.success();
        }
        // Missing watch, permissions or transient BLE failures wait for the next 3-hour slot.
        return Result.success();
    }
}
