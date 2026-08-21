package app.deterministic.todo.runtracker;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/** Narrow public boundary used by Flutter; movement storage stays inside runtracker. */
public final class MovementDashboardBridge {
    private static final String LIVE_PREFS = "movement_live_state";
    private static final int SESSION_PERMISSION_REQUEST = 7411;

    private MovementDashboardBridge() {}

    public static Map<String, Object> snapshot(Context context) {
        RunSession active = RunDatabase.get(context).runs().activeSession();
        SharedPreferences live = context.getSharedPreferences(LIVE_PREFS, Context.MODE_PRIVATE);
        Map<String, Object> value = new HashMap<>();
        boolean recording = active != null;
        value.put("recording", recording);
        value.put("session_id", recording ? active.id : 0L);
        value.put("activity_type", recording ? active.activityType : "");
        value.put("started_at_ms", recording ? active.startedAtMillis : 0L);
        long liveId = live.getLong("session_id", 0L);
        value.put("distance_m", recording && liveId == active.id
            ? Double.longBitsToDouble(live.getLong("distance_bits", 0L))
            : recording ? active.distanceMeters : 0.0);
        value.put("session_steps", recording && liveId == active.id
            ? live.getLong("session_steps", 0L) : 0L);
        value.put("accuracy_m", recording && liveId == active.id
            ? live.getFloat("accuracy_m", 0f) : 0f);
        value.put("gps_status", recording && liveId == active.id
            ? live.getString("gps_status", "Ricerca GPS…") : "GPS spento");
        value.put("passive_active", PassiveMovementAuditWorker.enabled(context));
        value.put("drive_configured", DriveTestExportManager.isConfigured(context));
        value.put("automatic_status", PassiveMovementAuditWorker.enabled(context)
            ? "Monitor passivo attivo" : "Monitor passivo spento");
        value.put("drive_status", DriveTestExportManager.status(context));
        return value;
    }

    public static String start(Activity activity, String requestedType) {
        ArrayList<String> required = new ArrayList<>();
        addMissing(activity, required, Manifest.permission.ACCESS_COARSE_LOCATION);
        addMissing(activity, required, Manifest.permission.ACCESS_FINE_LOCATION);
        if (Build.VERSION.SDK_INT >= 33)
            addMissing(activity, required, Manifest.permission.POST_NOTIFICATIONS);
        if (Build.VERSION.SDK_INT >= 29)
            addMissing(activity, required, Manifest.permission.ACTIVITY_RECOGNITION);
        if (!required.isEmpty()) {
            activity.requestPermissions(required.toArray(new String[0]), SESSION_PERMISSION_REQUEST);
            return "permission_requested";
        }
        String type = "run".equals(requestedType) ? "run" : "walk";
        ContextCompat.startForegroundService(activity, new Intent(activity, RunRecordingService.class)
            .setAction(RunRecordingService.ACTION_START)
            .putExtra(RunRecordingService.EXTRA_ACTIVITY_TYPE, type));
        return "started";
    }

    public static void stop(Context context) {
        context.startService(new Intent(context, RunRecordingService.class)
            .setAction(RunRecordingService.ACTION_STOP));
    }

    public static String uploadAll(Context context) {
        if (!DriveTestExportManager.isConfigured(context)) return "drive_not_configured";
        ManualDiagnosticExportScheduler.enqueue(context);
        return "scheduled";
    }

    static void recordLiveState(Context context, long sessionId, double distanceMeters,
                                long sessionSteps, float accuracyMeters, String gpsStatus) {
        context.getSharedPreferences(LIVE_PREFS, Context.MODE_PRIVATE).edit()
            .putLong("session_id", sessionId)
            .putLong("distance_bits", Double.doubleToRawLongBits(distanceMeters))
            .putLong("session_steps", sessionSteps)
            .putFloat("accuracy_m", accuracyMeters)
            .putString("gps_status", gpsStatus == null ? "" : gpsStatus)
            .apply();
    }

    private static void addMissing(Activity activity, ArrayList<String> required, String permission) {
        if (ContextCompat.checkSelfPermission(activity, permission) != PackageManager.PERMISSION_GRANTED)
            required.add(permission);
    }
}
