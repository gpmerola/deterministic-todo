package app.deterministic.todo.runtracker;

import android.content.ContentValues;
import android.content.Context;
import android.os.Build;
import android.provider.MediaStore;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

final class AutomaticTestGpxExporter {
    static final String PREFERENCES = "movement_test_export";
    static final String ENABLED = "enabled";
    static final String RELATIVE_PATH = "Download/DeterministicTodoTests";

    private AutomaticTestGpxExporter() {}

    static boolean isEnabled(Context context) {
        return Build.VERSION.SDK_INT >= 29 && context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(ENABLED, false);
    }

    static void setEnabled(Context context, boolean enabled) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, enabled).apply();
    }

    static boolean export(Context context, RunSession session, List<TrackPoint> points) {
        if (!isEnabled(context)) return false;
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, fileName(session));
        values.put(MediaStore.Downloads.MIME_TYPE, "application/gpx+xml");
        values.put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH);
        values.put(MediaStore.Downloads.IS_PENDING, 1);
        android.net.Uri uri = context.getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) return false;
        try (OutputStream output = context.getContentResolver().openOutputStream(uri, "w")) {
            if (output == null) {
                context.getContentResolver().delete(uri, null, null);
                return false;
            }
            output.write(GpxExporter.export(session, points).getBytes(StandardCharsets.UTF_8));
            ContentValues completed = new ContentValues();
            completed.put(MediaStore.Downloads.IS_PENDING, 0);
            context.getContentResolver().update(uri, completed, null, null);
            return true;
        } catch (Exception ignored) {
            context.getContentResolver().delete(uri, null, null);
            return false;
        }
    }

    static String fileName(RunSession session) {
        return "movement-test-" + session.activityType + "-" + session.startedAtMillis + ".gpx";
    }
}
