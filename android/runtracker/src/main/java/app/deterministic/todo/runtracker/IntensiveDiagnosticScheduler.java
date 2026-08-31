package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.Intent;

import androidx.core.content.ContextCompat;

/** Public boundary used by the host app and the movement screen. */
public final class IntensiveDiagnosticScheduler {
    private IntensiveDiagnosticScheduler() {}

    public static void enable(Context context) {
        IntensiveDiagnosticExperiment.enable(context, System.currentTimeMillis());
        ContextCompat.startForegroundService(context, new Intent(context, IntensiveDiagnosticService.class)
            .setAction(IntensiveDiagnosticService.ACTION_START));
    }

    public static void disable(Context context) {
        IntensiveDiagnosticExperiment.disable(context);
        context.startService(new Intent(context, IntensiveDiagnosticService.class)
            .setAction(IntensiveDiagnosticService.ACTION_STOP));
    }

    public static void refreshIfEnabled(Context context) {
        if (IntensiveDiagnosticExperiment.active(context)) {
            ContextCompat.startForegroundService(context, new Intent(context, IntensiveDiagnosticService.class)
                .setAction(IntensiveDiagnosticService.ACTION_START));
        }
    }
}
