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

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

public final class DiagnosticDriveWorker extends Worker {
    static final String INPUT_MANUAL_EXPORT = "manual_export";
    private static final String WORK = "todo-diagnostics-daily-drive";
    private static final String STARTUP_WORK = "todo-diagnostics-startup-drive";
    static final long PERIODIC_INTERVAL_HOURS = 3;
    enum ExportOutcome { SUCCESS, PERMISSION_FAILURE, RETRY }

    public DiagnosticDriveWorker(@NonNull Context context,
                                 @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    static void schedule(Context context) {
        Constraints connected = new Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build();
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
            DiagnosticDriveWorker.class, PERIODIC_INTERVAL_HOURS, TimeUnit.HOURS)
            .setConstraints(connected)
            .build();
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK, ExistingPeriodicWorkPolicy.UPDATE, request);

        OneTimeWorkRequest startupRequest = new OneTimeWorkRequest.Builder(
            DiagnosticDriveWorker.class)
            .setConstraints(connected)
            .setInitialDelay(1, TimeUnit.MINUTES)
            .build();
        WorkManager.getInstance(context).enqueueUniqueWork(
            STARTUP_WORK, ExistingWorkPolicy.REPLACE, startupRequest);
    }

    @NonNull @Override public Result doWork() {
        Context context = getApplicationContext();
        boolean manualExport = getInputData().getBoolean(INPUT_MANUAL_EXPORT, false);
        ExportOutcome outcome = exportNow(context, manualExport);
        return switch (outcome) {
            case SUCCESS -> Result.success();
            case PERMISSION_FAILURE -> Result.failure();
            case RETRY -> Result.retry();
        };
    }

    static ExportOutcome exportNow(Context context, boolean manualExport) {
        if (!DriveTestExportManager.isConfigured(context)) return ExportOutcome.SUCCESS;
        DiagnosticUploadDebugState.started(context, System.currentTimeMillis(), manualExport);
        try {
            String diagnostics = requiredPhase(context, "read_local_log",
                () -> readDiagnostics(context));
            long observedAt = System.currentTimeMillis();
            String slot = RollingDiagnosticBundle.nextSlot(context);
            String bundle = requiredPhase(context, "unified_generate", () ->
                RollingDiagnosticBundle.create(context, observedAt, manualExport, diagnostics)
                    .toString(2));
            requiredPhase(context, "unified_upload", () -> {
                DriveTestExportManager.writeRollingDiagnostics(context,
                    RollingDiagnosticBundle.fileName(slot), bundle);
                return null;
            });
            RollingDiagnosticBundle.markSuccessful(context, slot);
            DiagnosticUploadDebugState.succeeded(context, System.currentTimeMillis());
            return ExportOutcome.SUCCESS;
        } catch (SecurityException permissionLost) {
            DiagnosticUploadDebugState.failed(context, System.currentTimeMillis(), permissionLost);
            return ExportOutcome.PERMISSION_FAILURE;
        } catch (Exception transientFailure) {
            DiagnosticUploadDebugState.failed(context, System.currentTimeMillis(), transientFailure);
            return ExportOutcome.RETRY;
        }
    }

    private interface PhaseCall<T> { T run() throws Exception; }

    private static <T> T requiredPhase(Context context, String name, PhaseCall<T> call)
        throws Exception {
        long started = System.currentTimeMillis();
        DiagnosticUploadDebugState.phaseStarted(context, name, started);
        try {
            T value = call.run();
            DiagnosticUploadDebugState.phaseFinished(context, name,
                System.currentTimeMillis(), null, true);
            return value;
        } catch (Exception error) {
            DiagnosticUploadDebugState.phaseFinished(context, name,
                System.currentTimeMillis(), error, true);
            throw error;
        }
    }

    private static String readDiagnostics(Context context) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        File[] files = context.getFilesDir().listFiles((directory, name) ->
            name.equals("diagnostics.jsonl") || name.equals("diagnostics.jsonl.1")
                || name.matches("diagnostics-\\d{4}-\\d{2}-\\d{2}(-\\d+)?\\.jsonl"));
        if (files != null) {
            java.util.Arrays.sort(files, java.util.Comparator
                .comparingLong(File::lastModified).thenComparing(File::getName));
            long threshold = System.currentTimeMillis() - RollingDiagnosticBundle.WINDOW_MILLIS;
            for (File file : files) if (file.lastModified() >= threshold) append(file, output);
        }
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
