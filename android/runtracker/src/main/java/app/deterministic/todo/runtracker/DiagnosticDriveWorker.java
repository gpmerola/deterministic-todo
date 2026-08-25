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
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.TimeUnit;

public final class DiagnosticDriveWorker extends Worker {
    static final String INPUT_MANUAL_EXPORT = "manual_export";
    private static final String WORK = "todo-diagnostics-daily-drive";
    private static final String STARTUP_WORK = "todo-diagnostics-startup-drive";
    static final long PERIODIC_INTERVAL_HOURS = 1;

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
        if (!DriveTestExportManager.isConfigured(context)) return Result.success();
        IntensiveChunkUploader.uploadPending(context);
        boolean manualExport = getInputData().getBoolean(INPUT_MANUAL_EXPORT, false);
        DiagnosticUploadDebugState.started(context, System.currentTimeMillis(), manualExport);
        try {
            String diagnostics = requiredPhase(context, "read_local_log",
                () -> readDiagnostics(context));
            String bucket = LocalDateTime.now().format(DateTimeFormatter.ofPattern(
                manualExport ? "yyyy-MM-dd_HH-mm-ss" : "yyyy-MM-dd_HH"));
            String name = DiagnosticRetentionPolicy.PREFIX + bucket
                + DiagnosticRetentionPolicy.SUFFIX;
            if (!diagnostics.isEmpty()) {
                if (manualExport) name = "todo_diagnostics_manual_" + bucket + ".jsonl";
                final String finalName = name;
                requiredPhase(context, "raw_log_upload", () -> {
                    DriveTestExportManager.writeDailyDiagnostics(context, finalName, diagnostics);
                    return null;
                });
            }
            long observedAt = System.currentTimeMillis();
            String unifiedName = manualExport
                ? "unified_diagnostics_manual_" + bucket + ".json"
                : UnifiedDiagnosticReport.fileName(observedAt, ZoneId.systemDefault());
            requiredPhase(context, "unified_upload", () -> {
                DriveTestExportManager.writeUnifiedDiagnostics(context, unifiedName,
                    UnifiedDiagnosticReport.create(context, observedAt).toString(2));
                return null;
            });
            optionalPhase(context, "three_way_refresh", () -> {
                DriveTestExportManager.ThreeWayRefreshSummary summary =
                    DriveTestExportManager.refreshRecentThreeWayReports(context, 15);
                DiagnosticUploadDebugState.threeWaySummary(context, summary.attempted(),
                    summary.succeeded(), summary.firstFailureCode());
                if (summary.succeeded() != summary.attempted())
                    throw new ThreeWayRefreshPartialFailure();
                return null;
            });
            DiagnosticUploadDebugState.succeeded(context, System.currentTimeMillis());
            return Result.success();
        } catch (SecurityException permissionLost) {
            DiagnosticUploadDebugState.failed(context, System.currentTimeMillis(), permissionLost);
            return Result.failure();
        } catch (Exception transientFailure) {
            DiagnosticUploadDebugState.failed(context, System.currentTimeMillis(), transientFailure);
            return Result.retry();
        }
    }

    private interface PhaseCall<T> { T run() throws Exception; }

    private static final class ThreeWayRefreshPartialFailure extends Exception {}

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

    private static <T> void optionalPhase(Context context, String name, PhaseCall<T> call) {
        long started = System.currentTimeMillis();
        DiagnosticUploadDebugState.phaseStarted(context, name, started);
        try {
            call.run();
            DiagnosticUploadDebugState.phaseFinished(context, name,
                System.currentTimeMillis(), null, false);
        } catch (Exception error) {
            DiagnosticUploadDebugState.phaseFinished(context, name,
                System.currentTimeMillis(), error, false);
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
