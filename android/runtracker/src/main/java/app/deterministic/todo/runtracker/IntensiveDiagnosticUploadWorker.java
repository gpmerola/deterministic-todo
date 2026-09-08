package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

/** Isolated bounded uploader: it can retry or stall without blocking essential reports. */
public final class IntensiveDiagnosticUploadWorker extends Worker {
    public IntensiveDiagnosticUploadWorker(@NonNull Context context,
                                           @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    @NonNull @Override public Result doWork() {
        if (!DriveTestExportManager.isConfigured(getApplicationContext()))
            return Result.success();
        int remaining = IntensiveChunkUploader.uploadPending(getApplicationContext());
        return remaining == 0 ? Result.success() : Result.retry();
    }
}
