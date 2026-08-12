package app.deterministic.todo.runtracker;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.concurrent.TimeUnit;

public final class DiagnosticDriveWorker extends Worker {
    private static final String WORK = "todo-diagnostics-daily-drive";

    public DiagnosticDriveWorker(@NonNull Context context,
                                 @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    static void schedule(Context context) {
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
            DiagnosticDriveWorker.class, 24, TimeUnit.HOURS)
            .setInitialDelay(1, TimeUnit.MINUTES)
            .build();
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK, ExistingPeriodicWorkPolicy.KEEP, request);
    }

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        if (!DriveTestExportManager.isConfigured(context)) return Result.success();
        try {
            String diagnostics = readDiagnostics(context);
            if (diagnostics.isEmpty()) return Result.success();
            String name = DiagnosticRetentionPolicy.PREFIX + LocalDate.now()
                + DiagnosticRetentionPolicy.SUFFIX;
            DriveTestExportManager.writeDailyDiagnostics(context, name, diagnostics);
            return Result.success();
        } catch (SecurityException permissionLost) {
            return Result.failure();
        } catch (Exception transientFailure) {
            return Result.retry();
        }
    }

    private static String readDiagnostics(Context context) throws Exception {
        File current = new File(context.getFilesDir(), "diagnostics.jsonl");
        File previous = new File(context.getFilesDir(), "diagnostics.jsonl.1");
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        append(previous, output);
        append(current, output);
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    private static void append(File file, ByteArrayOutputStream output) throws Exception {
        if (!file.isFile()) return;
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
        }
    }
}
