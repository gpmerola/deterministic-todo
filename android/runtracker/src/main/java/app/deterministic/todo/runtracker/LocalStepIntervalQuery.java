package app.deterministic.todo.runtracker;

import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Process;
import java.util.Arrays;

/** Private minute data is only returned for an explicit shell query on Todo Test. */
final class LocalStepIntervalQuery {
    private static final String[] COLUMNS = {"schema_version", "source", "minute_start_ms",
        "overlap_ms", "sample_present", "steps", "steps_lower", "steps_upper",
        "prorated_steps_estimate", "passive_meters_estimate", "model_version",
        "profile_basis", "walking_stride_m", "running_stride_m", "zone_id", "imported_at_ms"};

    static Cursor query(Context context, Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        if (!context.getPackageName().endsWith(".dev") || Binder.getCallingUid() != Process.SHELL_UID)
            throw new SecurityException("Minute diagnostics require Todo Test and the ADB shell");
        if (selection != null || selectionArgs != null || sortOrder != null)
            throw new IllegalArgumentException("Use start_ms and end_ms URI parameters only");
        var range = new LocalStepIntervalReport.Range(
            Long.parseLong(uri.getQueryParameter("start_ms")),
            Long.parseLong(uri.getQueryParameter("end_ms")));
        String[] columns = projection == null ? COLUMNS : projection;
        int[] indices = new int[columns.length];
        for (int i = 0; i < columns.length; i++) {
            indices[i] = Arrays.asList(COLUMNS).indexOf(columns[i]);
            if (indices[i] < 0) throw new IllegalArgumentException("Unknown interval column");
        }
        var profile = MovementProfile.read(context);
        var timeline = ActivityTimeline.read(context);
        var db = RunDatabase.get(context);
        var rows = db.runInTransaction(() -> LocalStepIntervalReport.build(range,
            db.runs().localStepMinutes(range.firstMinute(), range.end()), timeline, profile));
        var cursor = new MatrixCursor(columns, rows.size());
        for (var row : rows) {
            var sample = row.sample();
            Object[] all = {1, "local_recording_api", row.minuteStart(), row.overlapMillis(),
                sample == null ? 0 : 1, sample == null ? null : sample.steps,
                row.stepsLower(), row.stepsUpper(), row.proratedSteps(), row.estimatedMeters(),
                1, "current_profile_and_timeline_no_gps_no_bip", profile.walkingStride(),
                profile.runningStride(), sample == null ? null : sample.zoneId,
                sample == null ? null : sample.importedAtMillis};
            Object[] selected = new Object[columns.length];
            for (int i = 0; i < selected.length; i++) selected[i] = all[indices[i]];
            cursor.addRow(selected);
        }
        return cursor;
    }
}
