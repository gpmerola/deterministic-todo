package app.deterministic.todo.runtracker;

import android.content.Context;

import java.io.File;
import java.util.List;

/** Bounded, serialized drain shared by passive and app-diagnostics workers. */
final class IntensiveChunkUploader {
    static final int MAXIMUM_PER_CYCLE = 8;

    private IntensiveChunkUploader() {}

    static synchronized void uploadPending(Context context) {
        long startedAt = System.currentTimeMillis();
        if (!IntensiveDiagnosticStore.checkpoint(context)) {
            int pending = IntensiveDiagnosticStore.pendingChunks(context).size();
            IntensiveUploadDebugState.finished(context, startedAt, pending, 0, 0,
                pending, "checkpoint_failed");
            return;
        }
        List<File> pending = IntensiveDiagnosticStore.pendingChunks(context);
        int attempted = 0, succeeded = 0;
        String firstFailure = null;
        for (File chunk : pending) {
            if (attempted >= MAXIMUM_PER_CYCLE) break;
            attempted++;
            DriveTestExportManager.ExportResult result =
                DriveTestExportManager.writeIntensiveDiagnosticChunk(context, chunk);
            if (!result.success()) {
                firstFailure = result.code();
                break;
            }
            IntensiveDiagnosticStore.uploaded(chunk);
            succeeded++;
        }
        int after = IntensiveDiagnosticStore.pendingChunks(context).size();
        IntensiveUploadDebugState.finished(context, startedAt, pending.size(), attempted,
            succeeded, after, firstFailure);
    }
}
