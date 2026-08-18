package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

final class PassiveMovementDebugState {
    static final int SCHEMA_VERSION = 1;
    private static final String PREFS = "movement_passive_debug";
    private static final long EXPECTED_INTERVAL_MILLIS = 60 * 60 * 1000L;

    private PassiveMovementDebugState() {}

    static void started(Context context, boolean driveConfigured) {
        long now = System.currentTimeMillis();
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", "running")
            .putString("result_code", "running")
            .putLong("last_attempt_ms", now)
            .putLong("next_expected_ms", now + EXPECTED_INTERVAL_MILLIS)
            .putBoolean("drive_configured", driveConfigured)
            .apply();
    }

    static void healthError(Context context, String error) {
        finish(context, "health_connect_error", safeCode(error));
    }

    static void exportFinished(Context context,
                               HealthConnectGateway.PassiveAudit audit,
                               LocalDateTime observedAt,
                               DriveTestExportManager.ExportResult result,
                               long driveWriteDurationMillis) {
        SharedPreferences profile = context.getSharedPreferences("movement_profile", Context.MODE_PRIVATE);
        double walkingStride = profile.getFloat("walking_stride_meters",
            (float) MovementEstimate.DEFAULT_STRIDE_METERS);
        double runningStride = profile.getFloat("running_stride_meters",
            (float) MixedMovementEstimate.DEFAULT_RUNNING_STRIDE_METERS);
        double weight = profile.getFloat("weight_kg", (float) MovementEstimate.DEFAULT_WEIGHT_KG);
        MixedMovementEstimate estimate = MixedMovementEstimate.calculate(
            audit.getWalkingSteps(), audit.getRunningSteps(), audit.getUnknownSteps(),
            audit.getExcludedSteps(), walkingStride, runningStride, weight);
        String fileName = snapshotFileName(observedAt);
        long now = System.currentTimeMillis();
        SharedPreferences.Editor editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", result.success() ? "success" : "drive_error")
            .putString("result_code", safeCode(result.code()))
            .putLong("last_finished_ms", now)
            .putLong("next_expected_ms", now + EXPECTED_INTERVAL_MILLIS)
            .putBoolean("drive_configured", result.configured())
            .putString("day", audit.getDay())
            .putString("zone_id", audit.getZoneId())
            .putString("file_name", fileName)
            .putLong("todo_steps", audit.getAllSteps())
            .putLong("walking_steps", estimate.walkingSteps())
            .putLong("running_steps", estimate.runningSteps())
            .putLong("unknown_steps", estimate.unknownSteps())
            .putLong("excluded_steps", estimate.excludedSteps())
            .putLong("excluded_vehicle_steps", audit.getVehicleSteps())
            .putLong("excluded_bicycle_steps", audit.getBicycleSteps())
            .putLong("still_conflict_steps", audit.getStillConflictSteps())
            .putLong("raw_step_record_count", audit.getRawStepRecordCount())
            .putLong("raw_step_record_steps", audit.getRawStepRecordSteps())
            .putLong("invalid_step_interval_records", audit.getInvalidStepIntervalRecords())
            .putLong("observed_steps_before_reconciliation",
                audit.getObservedStepsBeforeReconciliation())
            .putFloat("reconciliation_scale_factor",
                (float) audit.getReconciliationScaleFactor())
            .putLong("health_connect_read_ms", audit.getTotalReadDurationMillis())
            .putLong("drive_write_ms", driveWriteDurationMillis)
            .putLong("measurement_start_ms", audit.getIntervalStartMillis())
            .putLong("measurement_end_ms", audit.getIntervalEndMillis())
            .putFloat("todo_distance_m", (float) estimate.distanceMeters())
            .putFloat("all_steps_walking_baseline_distance_m", (float) (audit.getAllSteps() * walkingStride))
            .putFloat("todo_active_calories", (float) estimate.activeCalories());
        putNullableLong(editor, "fit_steps", audit.getFitSteps());
        putNullableFloat(editor, "fit_distance_m", audit.getFitDistanceMeters());
        putNullableFloat(editor, "fit_active_calories", audit.getFitActiveCalories());
        if (result.success()) editor.putLong("last_success_ms", now);
        editor.apply();
    }

    static Map<String, Object> values(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        LinkedHashMap<String, Object> values = new LinkedHashMap<>();
        values.put("schema_version", SCHEMA_VERSION);
        values.put("enabled", PassiveMovementAuditWorker.enabled(context) ? 1 : 0);
        values.put("phase", p.getString("phase", "never_run"));
        values.put("result_code", p.getString("result_code", "none"));
        values.put("drive_configured", p.getBoolean("drive_configured",
            DriveTestExportManager.isConfigured(context)) ? 1 : 0);
        addLong(values, p, "last_attempt_ms");
        addLong(values, p, "last_finished_ms");
        addLong(values, p, "last_success_ms");
        addLong(values, p, "next_expected_ms");
        values.put("day", p.getString("day", null));
        values.put("zone_id", p.getString("zone_id", null));
        values.put("file_name", p.getString("file_name", null));
        addLong(values, p, "todo_steps");
        addFloat(values, p, "todo_distance_m");
        addFloat(values, p, "todo_active_calories");
        addLong(values, p, "walking_steps");
        addLong(values, p, "running_steps");
        addLong(values, p, "unknown_steps");
        addLong(values, p, "excluded_steps");
        addLong(values, p, "excluded_vehicle_steps");
        addLong(values, p, "excluded_bicycle_steps");
        addLong(values, p, "still_conflict_steps");
        addLong(values, p, "raw_step_record_count");
        addLong(values, p, "raw_step_record_steps");
        addLong(values, p, "invalid_step_interval_records");
        addLong(values, p, "observed_steps_before_reconciliation");
        addFloat(values, p, "reconciliation_scale_factor");
        addLong(values, p, "health_connect_read_ms");
        addLong(values, p, "drive_write_ms");
        addLong(values, p, "measurement_start_ms");
        addLong(values, p, "measurement_end_ms");
        addFloat(values, p, "all_steps_walking_baseline_distance_m");
        addLong(values, p, "fit_steps");
        addFloat(values, p, "fit_distance_m");
        addFloat(values, p, "fit_active_calories");
        return values;
    }

    static String uiSummary(Context context) {
        Map<String, Object> v = values(context);
        if (v.get("last_attempt_ms") == null) return "Diagnostica ADB · nessuno snapshot ancora";
        return "Diagnostica ADB · " + v.get("phase") + " · " + v.get("result_code")
            + (v.get("file_name") == null ? "" : "\n" + v.get("file_name"));
    }

    static String snapshotFileName(LocalDateTime observedAt) {
        String bucket = observedAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd_HH"));
        return "movement_snapshot_" + bucket + ".json";
    }

    private static void finish(Context context, String phase, String code) {
        long now = System.currentTimeMillis();
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("phase", phase)
            .putString("result_code", code)
            .putLong("last_finished_ms", now)
            .putLong("next_expected_ms", now + EXPECTED_INTERVAL_MILLIS)
            .apply();
    }

    private static String safeCode(String code) {
        return code == null || code.isBlank() ? "unknown" : code;
    }

    private static void putNullableLong(SharedPreferences.Editor editor, String key, Long value) {
        if (value == null) editor.remove(key); else editor.putLong(key, value);
    }

    private static void putNullableFloat(SharedPreferences.Editor editor, String key, Double value) {
        if (value == null) editor.remove(key); else editor.putFloat(key, value.floatValue());
    }

    private static void addLong(Map<String, Object> values, SharedPreferences p, String key) {
        values.put(key, p.contains(key) ? p.getLong(key, 0) : null);
    }

    private static void addFloat(Map<String, Object> values, SharedPreferences p, String key) {
        values.put(key, p.contains(key) ? p.getFloat(key, 0) : null);
    }
}
