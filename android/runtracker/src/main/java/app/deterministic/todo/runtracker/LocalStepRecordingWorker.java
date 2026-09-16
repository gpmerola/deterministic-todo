package app.deterministic.todo.runtracker;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import java.util.concurrent.TimeUnit;

/** Deferred local import, independent of Drive, Fit comparison and diagnostic experiments. */
public final class LocalStepRecordingWorker extends Worker {
    public LocalStepRecordingWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    static void schedule(Context context) {
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("local_step_recording",
            ExistingPeriodicWorkPolicy.KEEP,
            new PeriodicWorkRequest.Builder(LocalStepRecordingWorker.class, 3, TimeUnit.HOURS).build());
    }

    @NonNull @Override public Result doWork() {
        LocalStepRecording.collect(getApplicationContext());
        return Result.success(); // Next periodic/foreground attempt; no rapid retry loop.
    }
}
