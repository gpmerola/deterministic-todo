package app.deterministic.todo.runtracker;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.TrafficStats;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Debug;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import android.provider.DocumentsContract;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

final class DriveTestExportManager {
    private static final String PREFS = "movement_drive_export";
    private static final String TREE_URI = "tree_uri";
    private static final String LAST_STATUS = "last_status";
    private static final String LAST_ERROR = "last_error";
    private static final String LAST_EXPORTED_AT = "last_exported_at";
    private static final String COMPARISON_STATUS = "comparison_status";
    private static final String COMPARISON_SUMMARY = "comparison_summary";
    private static final String LAST_PASSIVE_SAMPLE = "last_passive_sample_v1";
    private static final String DIRECTORY_TREE_URI = "directory_tree_uri_v1";
    private static final String DIRECTORY_ID_PREFIX = "directory_id_v1.";
    private static final long HEALTH_TIMEOUT_MILLIS = 8_000;
    private DriveTestExportManager() {}

    record ExportResult(boolean configured, boolean success, String code) {}
    interface Completion { void onComplete(ExportResult result); }

    static void exportBipUProbe(Context context, long startedAtMillis,
                                String connectionSource, String outcome,
                                Integer batteryPercent, Integer gattStatus,
                                Completion completion) {
        new Thread(() -> {
            if (!isConfigured(context)) {
                completion.onComplete(new ExportResult(false, false, "not_configured"));
                return;
            }
            try {
                long observedAt = System.currentTimeMillis();
                JSONObject report = new JSONObject()
                    .put("schema_version", 1)
                    .put("kind", "bip_u_read_only_probe")
                    .put("started_at_ms", startedAtMillis)
                    .put("observed_at_ms", observedAt)
                    .put("duration_ms", Math.max(0, observedAt - startedAtMillis))
                    .put("connection_source", connectionSource)
                    .put("outcome", outcome)
                    .put("battery_percent", batteryPercent == null ? JSONObject.NULL : batteryPercent)
                    .put("gatt_status", gattStatus == null ? JSONObject.NULL : gattStatus)
                    .put("app_version", appVersion(context))
                    .put("android_api", Build.VERSION.SDK_INT)
                    .put("privacy", new JSONObject()
                        .put("mac_recorded", false)
                        .put("auth_key_recorded", false)
                        .put("writes_to_watch", false));
                writeNewFile(context, "bip_u_probe_" + observedAt + ".json",
                    "application/json", report.toString(2));
                completion.onComplete(new ExportResult(true, true, "ok"));
            } catch (Exception error) {
                completion.onComplete(new ExportResult(true, false,
                    "bip_u_drive_failed_" + error.getClass().getSimpleName()));
            }
        }, "bip-u-drive-report").start();
    }

    static void exportBipUHeartRateProbe(Context context, long startedAtMillis,
                                         String connectionSource, String outcome,
                                         int sampleCount, Integer minimumBpm,
                                         Integer maximumBpm, Double meanBpm,
                                         Integer gattStatus, String failedStage,
                                         Integer authCharacteristicProperties,
                                         Integer lastWriteType,
                                         Completion completion) {
        new Thread(() -> {
            if (!isConfigured(context)) {
                completion.onComplete(new ExportResult(false, false, "not_configured"));
                return;
            }
            try {
                long observedAt = System.currentTimeMillis();
                JSONObject report = new JSONObject()
                    .put("schema_version", 2)
                    .put("kind", "bip_u_heart_rate_probe")
                    .put("started_at_ms", startedAtMillis)
                    .put("observed_at_ms", observedAt)
                    .put("duration_ms", Math.max(0, observedAt - startedAtMillis))
                    .put("connection_source", connectionSource)
                    .put("outcome", outcome)
                    .put("authentication", "challenge_response")
                    .put("sample_count", sampleCount)
                    .put("minimum_bpm", nullable(minimumBpm))
                    .put("maximum_bpm", nullable(maximumBpm))
                    .put("mean_bpm", nullable(meanBpm))
                    .put("gatt_status", nullable(gattStatus))
                    .put("failed_stage", nullable(failedStage))
                    .put("auth_characteristic_properties",
                        nullable(authCharacteristicProperties))
                    .put("last_write_type", nullable(lastWriteType))
                    .put("app_version", appVersion(context))
                    .put("android_api", Build.VERSION.SDK_INT)
                    .put("privacy", new JSONObject()
                        .put("mac_recorded", false)
                        .put("auth_key_recorded", false)
                        .put("raw_packets_recorded", false)
                        .put("persistent_configuration_writes", false)
                        .put("transient_control_writes", true));
                writeNewFile(context, "bip_u_heart_rate_probe_" + observedAt + ".json",
                    "application/json", report.toString(2));
                completion.onComplete(new ExportResult(true, true, "ok"));
            } catch (Exception error) {
                completion.onComplete(new ExportResult(true, false,
                    "bip_u_hr_drive_failed_" + error.getClass().getSimpleName()));
            }
        }, "bip-u-hr-drive-report").start();
    }

    static void exportBipUActivitySync(Context context, long startedAtMillis,
                                        String connectionSource, String outcome,
                                        long sampleCount, long insertedCount,
                                        long steps, long heartRateSampleCount,
                                        Integer gattStatus, Completion completion) {
        new Thread(() -> {
            if (!isConfigured(context)) {
                completion.onComplete(new ExportResult(false, false, "not_configured"));
                return;
            }
            try {
                long observedAt = System.currentTimeMillis();
                JSONObject report = new JSONObject()
                    .put("schema_version", 1)
                    .put("kind", "bip_u_activity_sync")
                    .put("started_at_ms", startedAtMillis)
                    .put("observed_at_ms", observedAt)
                    .put("duration_ms", Math.max(0, observedAt - startedAtMillis))
                    .put("connection_source", connectionSource)
                    .put("outcome", outcome)
                    .put("requested_window_hours", 24)
                    .put("sample_count", sampleCount)
                    .put("inserted_count", insertedCount)
                    .put("reported_steps", steps)
                    .put("heart_rate_sample_count", heartRateSampleCount)
                    .put("gatt_status", nullable(gattStatus))
                    .put("app_version", appVersion(context))
                    .put("privacy", new JSONObject()
                        .put("mac_recorded", false)
                        .put("auth_key_recorded", false)
                        .put("raw_packets_recorded", false)
                        .put("health_timeline_exported", false)
                        .put("activity_data_deleted_from_watch", false)
                        .put("persistent_configuration_writes", false));
                writeNewFile(context, "bip_u_activity_sync_" + observedAt + ".json",
                    "application/json", report.toString(2));
                completion.onComplete(new ExportResult(true, true, "ok"));
            } catch (Exception error) {
                completion.onComplete(new ExportResult(true, false,
                    "bip_u_activity_drive_failed_" + error.getClass().getSimpleName()));
            }
        }, "bip-u-activity-drive-report").start();
    }

    static void setFolder(Context context, Uri uri, int resultFlags) {
        int takeFlags = resultFlags & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        if ((takeFlags & Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == 0) {
            throw new SecurityException("write permission missing");
        }
        context.getContentResolver().takePersistableUriPermission(uri,
            takeFlags);
        if (!canReadFolder(context, uri)) throw new SecurityException("folder unavailable");
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(TREE_URI, uri.toString())
            .putString(LAST_STATUS, "ready")
            .remove(DIRECTORY_TREE_URI)
            .remove(DIRECTORY_ID_PREFIX + "sessions")
            .remove(DIRECTORY_ID_PREFIX + "passive")
            .remove(DIRECTORY_ID_PREFIX + "intensive")
            .remove(DIRECTORY_ID_PREFIX + "app_diagnostics")
            .remove(DIRECTORY_ID_PREFIX + "bip_u")
            .remove(LAST_ERROR)
            .apply();
    }

    static boolean isConfigured(Context context) { return tree(context) != null; }

    static void captureStart(Context context, long id) {
        android.content.SharedPreferences.Editor e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        e.putLong(id + ".elapsed", android.os.SystemClock.elapsedRealtime());
        e.putLong(id + ".cpu", Process.getElapsedCpuTime());
        e.putLong(id + ".rx", TrafficStats.getUidRxBytes(Process.myUid()));
        e.putLong(id + ".tx", TrafficStats.getUidTxBytes(Process.myUid()));
        e.putInt(id + ".battery", battery(context));
        e.remove(id + ".direct_step_timeline");
        e.apply();
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(id + ".steps", m.steps).apply(); }
            public void onPermissionRequired() {} public void onUnavailable() {} public void onError() {}
        });
    }

    static void captureDirectSteps(Context context, long id, long steps, String sensorStatus) {
        if (id == 0) return;
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(id + ".direct_steps", Math.max(0, steps))
            .putString(id + ".direct_step_status", sensorStatus)
            .apply();
    }

    static long directSteps(Context context, long id) {
        return Math.max(0, context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(id + ".direct_steps", 0));
    }

    static DirectStepTimeline directStepTimeline(Context context, long id) {
        return DirectStepTimeline.decode(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(id + ".direct_step_timeline", null));
    }

    static void captureDirectStepTimeline(Context context, long id, DirectStepTimeline timeline) {
        if (id == 0 || timeline == null) return;
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(id + ".direct_step_timeline", timeline.encode()).apply();
    }

    static void captureGoogleFitComparison(Context context, long id,
                                           HealthConnectGateway.GoogleFitComparison comparison) {
        if (id == 0 || comparison == null) return;
        android.content.SharedPreferences preferences = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String fingerprint = comparisonFingerprint(comparison);
        String previousFingerprint = preferences.getString(id + ".fit_fingerprint", null);
        android.content.SharedPreferences.Editor editor = preferences.edit()
            .putString(id + ".fit_fingerprint", fingerprint)
            .putLong(id + ".fit_local_steps", comparison.getLocalSteps())
            .putFloat(id + ".fit_local_distance_m", (float) comparison.getLocalDistanceMeters());
        // WorkManager intentionally rereads Fit while it is settling. Keep the immutable
        // sidecar identity stable when the actual values did not change, otherwise every
        // retry would create an indistinguishable file on Drive.
        if (!fingerprint.equals(previousFingerprint)
            || !preferences.contains(id + ".fit_observed_at")) {
            editor.putLong(id + ".fit_observed_at", System.currentTimeMillis());
        }
        if (comparison.getSteps() != null) editor.putLong(id + ".fit_steps", comparison.getSteps());
        else editor.remove(id + ".fit_steps");
        if (comparison.getDistanceMeters() != null) editor.putFloat(id + ".fit_distance_m", comparison.getDistanceMeters().floatValue());
        else editor.remove(id + ".fit_distance_m");
        if (comparison.getActiveCalories() != null) editor.putFloat(id + ".fit_active_calories", comparison.getActiveCalories().floatValue());
        else editor.remove(id + ".fit_active_calories");
        String fitDistance = comparison.getDistanceMeters() == null ? "—" :
            String.format(java.util.Locale.ITALY, "%.3f km", comparison.getDistanceMeters() / 1000);
        String distanceDelta = comparison.getDistanceMeters() == null || comparison.getDistanceMeters() <= 0 ? "—" :
            String.format(java.util.Locale.ITALY, "%+.1f%%", 100 * (comparison.getLocalDistanceMeters() - comparison.getDistanceMeters()) / comparison.getDistanceMeters());
        String fitSteps = comparison.getSteps() == null ? "—" : String.format(java.util.Locale.ITALY, "%,d", comparison.getSteps());
        String stepDelta = comparison.getSteps() == null || comparison.getSteps() <= 0 ? "—" :
            String.format(java.util.Locale.ITALY, "%+.1f%%", 100.0 * (comparison.getLocalSteps() - comparison.getSteps()) / comparison.getSteps());
        editor.putString(COMPARISON_SUMMARY, String.format(java.util.Locale.ITALY,
            "Google Fit %s · %s passi\nTodo %.3f km (%s) · %,d passi (%s)",
            fitDistance, fitSteps, comparison.getLocalDistanceMeters() / 1000,
            distanceDelta, comparison.getLocalSteps(), stepDelta));
        editor.apply();
    }

    static String comparisonFingerprint(HealthConnectGateway.GoogleFitComparison comparison) {
        return comparison.getLocalSteps() + "|"
            + Double.doubleToLongBits(comparison.getLocalDistanceMeters()) + "|"
            + nullableNumberFingerprint(comparison.getSteps()) + "|"
            + nullableNumberFingerprint(comparison.getDistanceMeters()) + "|"
            + nullableNumberFingerprint(comparison.getActiveCalories());
    }

    private static String nullableNumberFingerprint(Number value) {
        return value == null ? "null" : Long.toUnsignedString(
            Double.doubleToLongBits(value.doubleValue()));
    }

    static void setComparisonStatus(Context context, String status) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(COMPARISON_STATUS, status).apply();
    }

    static void captureComparisonAttempt(Context context, long id, String status, int attempts) {
        captureComparisonAttempt(context, id, status, attempts, null);
    }

    static void captureComparisonAttempt(Context context, long id, String status, int attempts,
                                         String errorCode) {
        android.content.SharedPreferences.Editor editor = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(COMPARISON_STATUS, status)
            .putString(id + ".comparison_status", status)
            .putInt(id + ".comparison_attempts", attempts)
            .putLong(id + ".comparison_last_attempt_at", System.currentTimeMillis());
        if (errorCode == null) editor.remove(id + ".comparison_error_code");
        else editor.putString(id + ".comparison_error_code", errorCode);
        editor.apply();
    }

    static String comparisonStatus(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(COMPARISON_STATUS, "idle");
    }

    static String comparisonStatus(Context context, long sessionId) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(sessionId + ".comparison_status", "not_scheduled");
    }

    static String comparisonSummary(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(COMPARISON_SUMMARY, "Confronto completato e salvato su Drive");
    }

    static String status(Context context) {
        android.content.SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String status = p.getString(LAST_STATUS, isConfigured(context) ? "ready" : "not_configured");
        if ("success".equals(status)) return "Ultimo caricamento Drive completato";
        if ("exporting".equals(status)) return "Export Drive in corso…";
        if ("failed".equals(status)) return "Ultimo export Drive non riuscito · " + p.getString(LAST_ERROR, "errore_sconosciuto");
        if ("ready".equals(status)) return "Cartella Drive pronta · nessun export completato";
        return "Cartella Drive non collegata";
    }

    static void finish(Context context, RunSession session, List<TrackPoint> points, Completion completion) {
        StrideCalibrator.record(context, session, directSteps(context, session.id));
        if (!isConfigured(context)) {
            completion.onComplete(new ExportResult(false, false, "not_configured"));
            return;
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(LAST_STATUS, "exporting").apply();
        AtomicBoolean exportStarted = new AtomicBoolean(false);
        class ExportStarter {
            void start(Long stepsEnd, String healthStatus) {
                if (!exportStarted.compareAndSet(false, true)) return;
                new Thread(() -> completion.onComplete(write(context, session, points, stepsEnd, healthStatus)),
                    "movement-drive-export").start();
            }
        }
        ExportStarter starter = new ExportStarter();
        new Handler(Looper.getMainLooper()).postDelayed(
            () -> starter.start(null, "timeout"), HEALTH_TIMEOUT_MILLIS
        );
        HealthConnectGateway.refreshToday(context, new HealthConnectGateway.Callback() {
            public void onSuccess(DailyMovement m) { starter.start(m.steps, "fresh"); }
            public void onPermissionRequired() { starter.start(null, "permission_required"); }
            public void onUnavailable() { starter.start(null, "unavailable"); }
            public void onError() { starter.start(null, "error"); }
        });
    }

    static void exportComparison(Context context, RunSession session, Completion completion) {
        new Thread(() -> completion.onComplete(writeComparison(context, session)),
            "movement-drive-comparison").start();
    }

    private static ExportResult writeComparison(Context c, RunSession s) {
        if (!isConfigured(c)) return new ExportResult(false, false, "not_configured");
        try {
            android.content.SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            long observedAt = p.getLong(s.id + ".fit_observed_at", 0);
            if (observedAt <= 0) return new ExportResult(true, false, "comparison_missing");
            String base = String.format(java.util.Locale.ROOT, "%d_%s_session-%06d",
                s.startedAtMillis, s.activityType, s.id);
            JSONObject fit = new JSONObject()
                .put("schema_version", 1)
                .put("session_id", s.id)
                .put("observed_at_ms", observedAt)
                .put("started_at_ms", s.startedAtMillis)
                .put("ended_at_ms", s.endedAtMillis)
                .put("fit_steps", p.contains(s.id + ".fit_steps") ? p.getLong(s.id + ".fit_steps", 0) : JSONObject.NULL)
                .put("fit_distance_m", p.contains(s.id + ".fit_distance_m") ? p.getFloat(s.id + ".fit_distance_m", 0) : JSONObject.NULL)
                .put("fit_active_calories", p.contains(s.id + ".fit_active_calories") ? p.getFloat(s.id + ".fit_active_calories", 0) : JSONObject.NULL)
                .put("local_steps", p.getLong(s.id + ".fit_local_steps", 0))
                .put("local_distance_m", p.getFloat(s.id + ".fit_local_distance_m", 0));
            writeNewFile(c, base + "_comparison-" + observedAt + ".json",
                "application/json", fit.toString(2));
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            String code = "drive_comparison_failed_" + error.getClass().getSimpleName();
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "failed").putString(LAST_ERROR, code).apply();
            return new ExportResult(true, false, code);
        }
    }

    static ExportResult writePassiveAudit(Context c, HealthConnectGateway.PassiveAudit audit) {
        return writePassiveReport(c, audit, "passive_daily_audit",
            "daily_audit_" + audit.getDay() + ".json", System.currentTimeMillis());
    }

    static ExportResult writePassiveSnapshot(Context c,
                                               HealthConnectGateway.PassiveAudit audit,
                                               LocalDateTime observedAt) {
        String bucket = observedAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd_HH"));
        return writePassiveReport(c, audit, "passive_intraday_snapshot",
            "movement_snapshot_" + bucket + ".json", System.currentTimeMillis());
    }

    private static ExportResult writePassiveReport(Context c,
                                                     HealthConnectGateway.PassiveAudit audit,
                                                     String kind,
                                                     String fileName,
                                                     long observedAtMillis) {
        if (!isConfigured(c)) return new ExportResult(false, false, "not_configured");
        try {
            android.content.SharedPreferences profile = c.getSharedPreferences("movement_profile", Context.MODE_PRIVATE);
            double stride = profile.getFloat("walking_stride_meters",
                (float) MovementEstimate.DEFAULT_STRIDE_METERS);
            double runningStride = profile.getFloat("running_stride_meters",
                (float) MixedMovementEstimate.DEFAULT_RUNNING_STRIDE_METERS);
            double weight = profile.getFloat("weight_kg", (float) MovementEstimate.DEFAULT_WEIGHT_KG);
            android.content.SharedPreferences classifier = c.getSharedPreferences(
                "movement_activity_timeline", Context.MODE_PRIVATE);
            MixedMovementEstimate estimate = MixedMovementEstimate.calculate(
                audit.getWalkingSteps(), audit.getRunningSteps(), audit.getUnknownSteps(),
                audit.getExcludedSteps(), stride, runningStride, weight);
            PassiveSnapshotDelta.Sample currentSample = new PassiveSnapshotDelta.Sample(
                audit.getDay(), observedAtMillis, audit.getAllSteps(), estimate.distanceMeters(),
                audit.getFitSteps(), audit.getFitDistanceMeters(), estimate.walkingSteps(),
                estimate.runningSteps(), estimate.unknownSteps(), estimate.excludedSteps(),
                audit.getStillConflictSteps());
            PassiveSnapshotDelta.Delta delta = PassiveSnapshotDelta.between(
                readPassiveSample(c), currentSample);
            boolean intraday = "passive_intraday_snapshot".equals(kind);
            JSONObject json = new JSONObject()
                .put("schema_version", 5)
                .put("kind", kind)
                .put("day", audit.getDay())
                .put("zone_id", audit.getZoneId())
                .put("observed_at_ms", observedAtMillis)
                .put("measurement_window", new JSONObject()
                    .put("start_ms", audit.getIntervalStartMillis())
                    .put("end_ms", audit.getIntervalEndMillis())
                    .put("duration_ms", audit.getIntervalEndMillis() - audit.getIntervalStartMillis())
                    .put("observation_delay_ms", Math.max(0,
                        observedAtMillis - audit.getIntervalEndMillis())))
                .put("collection_performance", new JSONObject()
                    .put("all_sources_aggregate_ms", audit.getAllSourcesAggregateDurationMillis())
                    .put("google_fit_aggregate_ms", audit.getGoogleFitAggregateDurationMillis())
                    .put("step_record_read_and_classification_ms", audit.getClassificationDurationMillis())
                    .put("health_connect_total_ms", audit.getTotalReadDurationMillis()))
                .put("activity_classifier", new JSONObject()
                    .put("status", classifier.getString("registration_status", "unknown"))
                    .put("status_observed_at_ms", classifier.contains("registration_observed_at_ms")
                        ? classifier.getLong("registration_observed_at_ms", 0) : JSONObject.NULL)
                    .put("timeline_events", ActivityTimeline.read(c).size())
                    .put("exclusion_threshold", 0.80)
                    .put("records_meeting_exclusion_threshold",
                        audit.getExclusionThresholdRecordCount()))
                .put("step_records", new JSONObject()
                    .put("record_count", audit.getRawStepRecordCount())
                    .put("record_steps_before_aggregate_reconciliation",
                        audit.getRawStepRecordSteps())
                    .put("classified_steps_before_aggregate_reconciliation",
                        audit.getObservedStepsBeforeReconciliation())
                    .put("classification_before_reconciliation", new JSONObject()
                        .put("walking", audit.getWalkingStepsBeforeReconciliation())
                        .put("running", audit.getRunningStepsBeforeReconciliation())
                        .put("unknown", audit.getUnknownStepsBeforeReconciliation())
                        .put("vehicle", audit.getVehicleStepsBeforeReconciliation())
                        .put("bicycle", audit.getBicycleStepsBeforeReconciliation())
                        .put("still_with_steps", audit.getStillConflictStepsBeforeReconciliation()))
                    .put("aggregate_steps", audit.getAllSteps())
                    .put("aggregate_minus_record_steps",
                        audit.getAllSteps() - audit.getRawStepRecordSteps())
                    .put("reconciliation_scale_factor", audit.getReconciliationScaleFactor())
                    .put("invalid_or_zero_duration_records",
                        audit.getInvalidStepIntervalRecords())
                    .put("google_fit_record_count", audit.getGoogleFitStepRecordCount())
                    .put("google_fit_record_steps", audit.getGoogleFitRawRecordSteps())
                    .put("other_origin_record_count", audit.getOtherStepRecordCount())
                    .put("earliest_start_ms", nullable(audit.getEarliestStepRecordStartMillis()))
                    .put("latest_end_ms", nullable(audit.getLatestStepRecordEndMillis()))
                    .put("latest_record_age_ms", audit.getLatestStepRecordEndMillis() == null
                        ? JSONObject.NULL : Math.max(0, audit.getIntervalEndMillis()
                            - audit.getLatestStepRecordEndMillis())))
                .put("raw_activity_overlap_durations_ms", new JSONObject()
                    .put("walking", audit.getWalkingRecordDurationMillis())
                    .put("running", audit.getRunningRecordDurationMillis())
                    .put("unknown", audit.getUnknownRecordDurationMillis())
                    .put("vehicle", audit.getVehicleRecordDurationMillis())
                    .put("bicycle", audit.getBicycleRecordDurationMillis())
                    .put("still_with_steps", audit.getStillRecordDurationMillis()))
                .put("todo", new JSONObject()
                    .put("steps", audit.getAllSteps())
                    .put("estimated_distance_m", estimate.distanceMeters())
                    .put("all_steps_walking_baseline_distance_m", audit.getAllSteps() * stride)
                    .put("estimated_active_calories", estimate.activeCalories())
                    .put("walking_steps", estimate.walkingSteps())
                    .put("running_steps", estimate.runningSteps())
                    .put("unknown_steps", estimate.unknownSteps())
                    .put("excluded_steps", estimate.excludedSteps())
                    .put("excluded_vehicle_steps", audit.getVehicleSteps())
                    .put("excluded_bicycle_steps", audit.getBicycleSteps())
                    .put("still_conflict_steps_included_as_unknown", audit.getStillConflictSteps())
                    .put("walking_stride_m", stride)
                    .put("running_stride_m", runningStride)
                    .put("weight_kg", weight))
                .put("health_connect_all_sources", new JSONObject()
                    .put("distance_m", audit.getAllDistanceMeters() == null ? JSONObject.NULL : audit.getAllDistanceMeters())
                    .put("active_calories", audit.getAllActiveCalories() == null ? JSONObject.NULL : audit.getAllActiveCalories()))
                .put("google_fit", new JSONObject()
                    .put("steps", audit.getFitSteps() == null ? JSONObject.NULL : audit.getFitSteps())
                    .put("distance_m", audit.getFitDistanceMeters() == null ? JSONObject.NULL : audit.getFitDistanceMeters())
                    .put("active_calories", audit.getFitActiveCalories() == null ? JSONObject.NULL : audit.getFitActiveCalories()))
                .put("comparison", comparisonJson(audit, estimate))
                .put("delta_from_previous_snapshot", intraday
                    ? deltaJson(delta) : JSONObject.NULL);
            writeNewFile(c, fileName, "application/json", json.toString(2));
            if (intraday) storePassiveSample(c, currentSample);
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            return new ExportResult(true, false, "drive_audit_failed_" + error.getClass().getSimpleName());
        }
    }

    private static JSONObject comparisonJson(HealthConnectGateway.PassiveAudit audit,
                                               MixedMovementEstimate estimate) throws Exception {
        JSONObject result = new JSONObject();
        result.put("steps", comparisonMetric(audit.getAllSteps(), audit.getFitSteps()));
        result.put("distance_m", comparisonMetric(estimate.distanceMeters(),
            audit.getFitDistanceMeters()));
        result.put("active_calories", comparisonMetric(estimate.activeCalories(),
            audit.getFitActiveCalories()));
        result.put("todo_effective_stride_m_per_included_step",
            includedSteps(estimate) == 0 ? JSONObject.NULL
                : estimate.distanceMeters() / includedSteps(estimate));
        result.put("fit_effective_stride_m_per_step",
            audit.getFitSteps() == null || audit.getFitSteps() == 0
                || audit.getFitDistanceMeters() == null ? JSONObject.NULL
                : audit.getFitDistanceMeters() / audit.getFitSteps());
        result.put("unknown_share_of_all_steps",
            share(estimate.unknownSteps(), audit.getAllSteps()));
        result.put("excluded_share_of_all_steps",
            share(estimate.excludedSteps(), audit.getAllSteps()));
        result.put("still_conflict_share_of_all_steps",
            share(audit.getStillConflictSteps(), audit.getAllSteps()));
        result.put("fit_data_complete_for_core_comparison",
            audit.getFitSteps() != null && audit.getFitDistanceMeters() != null);
        result.put("quality_flags", qualityFlags(audit, estimate));
        return result;
    }

    private static JSONObject comparisonMetric(double todo, Number fit) throws Exception {
        JSONObject value = new JSONObject().put("todo", todo)
            .put("fit", fit == null ? JSONObject.NULL : fit);
        if (fit == null) return value.put("delta", JSONObject.NULL)
            .put("absolute_delta", JSONObject.NULL).put("percent_vs_fit", JSONObject.NULL);
        double reference = fit.doubleValue();
        double delta = todo - reference;
        return value.put("delta", delta).put("absolute_delta", Math.abs(delta))
            .put("percent_vs_fit", reference == 0 ? JSONObject.NULL : delta * 100.0 / reference);
    }

    private static Object share(long numerator, long denominator) {
        return denominator == 0 ? JSONObject.NULL : numerator / (double) denominator;
    }

    private static JSONArray qualityFlags(HealthConnectGateway.PassiveAudit audit,
                                           MixedMovementEstimate estimate) {
        JSONArray flags = new JSONArray();
        if (audit.getFitSteps() == null) flags.put("fit_steps_missing");
        if (audit.getFitDistanceMeters() == null) flags.put("fit_distance_missing");
        if (audit.getRawStepRecordCount() == 0 && audit.getAllSteps() > 0)
            flags.put("aggregate_without_raw_step_records");
        if (audit.getInvalidStepIntervalRecords() > 0) flags.put("invalid_step_intervals");
        if (audit.getRawStepRecordSteps() != audit.getAllSteps())
            flags.put("raw_records_reconciled_to_aggregate");
        if (audit.getAllSteps() > 0 && estimate.unknownSteps() / (double) audit.getAllSteps() >= 0.50)
            flags.put("majority_steps_unknown");
        if (audit.getAllSteps() > 0 && audit.getStillConflictSteps() / (double) audit.getAllSteps() >= 0.20)
            flags.put("material_still_step_conflict");
        if (audit.getLatestStepRecordEndMillis() != null
            && audit.getIntervalEndMillis() - audit.getLatestStepRecordEndMillis() > 2 * 60 * 60 * 1000L)
            flags.put("raw_step_records_over_two_hours_old");
        return flags;
    }

    private static long includedSteps(MixedMovementEstimate estimate) {
        return estimate.walkingSteps() + estimate.runningSteps() + estimate.unknownSteps();
    }

    private static JSONObject deltaJson(PassiveSnapshotDelta.Delta delta) throws Exception {
        JSONObject json = new JSONObject().put("valid", delta.valid()).put("reason", delta.reason())
            .put("start_ms", delta.startMillis()).put("end_ms", delta.endMillis())
            .put("duration_ms", delta.durationMillis());
        if (!delta.valid()) return json;
        JSONObject todo = new JSONObject().put("steps", delta.todoSteps())
            .put("distance_m", delta.todoDistanceMeters())
            .put("walking_steps", delta.walkingSteps())
            .put("running_steps", delta.runningSteps())
            .put("unknown_steps", delta.unknownSteps())
            .put("excluded_steps", delta.excludedSteps())
            .put("still_conflict_steps", delta.stillConflictSteps());
        JSONObject fit = new JSONObject()
            .put("steps", nullable(delta.fitSteps()))
            .put("distance_m", nullable(delta.fitDistanceMeters()));
        json.put("todo", todo).put("google_fit", fit)
            .put("comparison", new JSONObject()
                .put("steps", comparisonMetric(delta.todoSteps(), delta.fitSteps()))
                .put("distance_m", comparisonMetric(delta.todoDistanceMeters(),
                    delta.fitDistanceMeters())));
        return json;
    }

    private static PassiveSnapshotDelta.Sample readPassiveSample(Context context) {
        String encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(LAST_PASSIVE_SAMPLE, null);
        if (encoded == null) return null;
        try {
            JSONObject json = new JSONObject(encoded);
            return new PassiveSnapshotDelta.Sample(json.getString("day"),
                json.getLong("observed_at_ms"), json.getLong("todo_steps"),
                json.getDouble("todo_distance_m"), nullableLong(json, "fit_steps"),
                nullableDouble(json, "fit_distance_m"), json.getLong("walking_steps"),
                json.getLong("running_steps"), json.getLong("unknown_steps"),
                json.getLong("excluded_steps"), json.getLong("still_conflict_steps"));
        } catch (Exception ignored) { return null; }
    }

    private static void storePassiveSample(Context context, PassiveSnapshotDelta.Sample sample)
        throws Exception {
        JSONObject json = new JSONObject().put("day", sample.day())
            .put("observed_at_ms", sample.observedAtMillis())
            .put("todo_steps", sample.todoSteps())
            .put("todo_distance_m", sample.todoDistanceMeters())
            .put("fit_steps", nullable(sample.fitSteps()))
            .put("fit_distance_m", nullable(sample.fitDistanceMeters()))
            .put("walking_steps", sample.walkingSteps())
            .put("running_steps", sample.runningSteps())
            .put("unknown_steps", sample.unknownSteps())
            .put("excluded_steps", sample.excludedSteps())
            .put("still_conflict_steps", sample.stillConflictSteps());
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(LAST_PASSIVE_SAMPLE, json.toString()).apply();
    }

    private static Object nullable(Object value) {
        return value == null ? JSONObject.NULL : value;
    }

    private static Long nullableLong(JSONObject json, String key) {
        return json.isNull(key) ? null : json.optLong(key);
    }

    private static Double nullableDouble(JSONObject json, String key) {
        return json.isNull(key) ? null : json.optDouble(key);
    }

    private static ExportResult write(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd, String healthStatus) {
        android.content.SharedPreferences.Editor status = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        try {
            String base = String.format(java.util.Locale.ROOT, "%d_%s_session-%06d", s.startedAtMillis, s.activityType, s.id);
            writeFile(c, base + ".gpx", "application/gpx+xml", GpxExporter.export(s, points));
            writeFile(c, base + "_diagnostics.json", "application/json", diagnostics(c, s, points, stepsEnd, healthStatus).toString(2));
            status.putString(LAST_STATUS, "success").remove(LAST_ERROR)
                .putLong(LAST_EXPORTED_AT, System.currentTimeMillis()).apply();
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            String code = "drive_write_failed_" + error.getClass().getSimpleName();
            status.putString(LAST_STATUS, "failed").putString(LAST_ERROR, code).apply();
            return new ExportResult(true, false, code);
        }
    }

    private static JSONObject diagnostics(Context c, RunSession s, List<TrackPoint> points, Long stepsEnd, String healthStatus) throws Exception {
        android.content.SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSONObject reasons = new JSONObject(); JSONArray samples = new JSONArray(); int accepted = 0; double accuracySum = 0; float accuracyMax = 0;
        for (TrackPoint x : points) {
            if (x.accepted) accepted++; else reasons.put(x.rejectionReason, reasons.optInt(x.rejectionReason) + 1);
            accuracySum += x.accuracyMeters; accuracyMax = Math.max(accuracyMax, x.accuracyMeters);
            samples.put(new JSONObject().put("time_ms", x.timestampMillis).put("lat", x.latitude).put("lon", x.longitude)
                .put("accuracy_m", x.accuracyMeters).put("accepted", x.accepted).put("reason", x.rejectionReason)
                .put("distance_total_m", x.accumulatedDistanceMeters));
        }
        long elapsed0 = p.getLong(s.id + ".elapsed", 0), cpu0 = p.getLong(s.id + ".cpu", 0);
        long rx0 = p.getLong(s.id + ".rx", -1), tx0 = p.getLong(s.id + ".tx", -1), steps0 = p.getLong(s.id + ".steps", -1);
        long directSteps = p.getLong(s.id + ".direct_steps", -1);
        String directStepStatus = p.getString(s.id + ".direct_step_status", "not_recorded");
        JSONArray directStepSamples = new JSONArray();
        for (DirectStepTimeline.Sample sample : directStepTimeline(c, s.id).snapshot()) {
            directStepSamples.put(new JSONObject().put("time_ms", sample.timeMillis())
                .put("steps", sample.steps()).put("status", sample.status()));
        }
        long exportedAt = System.currentTimeMillis();
        long fitObservedAt = p.getLong(s.id + ".fit_observed_at", -1);
        String automationStatus = p.getString(s.id + ".comparison_status", "not_scheduled");
        JSONObject fit = new JSONObject()
            .put("status", fitObservedAt < 0 ? "not_compared" : "available")
            .put("automation_status", automationStatus)
            .put("attempt_count", p.getInt(s.id + ".comparison_attempts", 0))
            .put("last_attempt_at_ms", p.contains(s.id + ".comparison_last_attempt_at")
                ? p.getLong(s.id + ".comparison_last_attempt_at", 0) : JSONObject.NULL);
        fit.put("error_code", p.contains(s.id + ".comparison_error_code")
            ? p.getString(s.id + ".comparison_error_code", "health_error_unknown")
            : JSONObject.NULL);
        if (fitObservedAt >= 0) {
            fit.put("observed_at_ms", fitObservedAt)
                .put("steps", p.contains(s.id + ".fit_steps") ? p.getLong(s.id + ".fit_steps", 0) : JSONObject.NULL)
                .put("distance_m", p.contains(s.id + ".fit_distance_m") ? p.getFloat(s.id + ".fit_distance_m", 0) : JSONObject.NULL)
                .put("active_calories", p.contains(s.id + ".fit_active_calories") ? p.getFloat(s.id + ".fit_active_calories", 0) : JSONObject.NULL)
                .put("local_steps", p.getLong(s.id + ".fit_local_steps", 0))
                .put("local_distance_m", p.getFloat(s.id + ".fit_local_distance_m", 0));
        }
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo(); ((ActivityManager)c.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
        return new JSONObject().put("schema_version", 1).put("session_id", s.id).put("activity", s.activityType)
            .put("started_at_ms", s.startedAtMillis).put("ended_at_ms", s.endedAtMillis).put("duration_ms", s.endedAtMillis - s.startedAtMillis)
            .put("exported_at_ms", exportedAt)
            .put("distance_m", s.distanceMeters).put("steps_start_daily", steps0 < 0 ? JSONObject.NULL : steps0)
            .put("steps_end_daily", stepsEnd == null ? JSONObject.NULL : stepsEnd)
            .put("steps_end_observed_at_ms", stepsEnd == null ? JSONObject.NULL : exportedAt)
            .put("steps_delta", stepsEnd == null || steps0 < 0 || stepsEnd < steps0 ? JSONObject.NULL : stepsEnd - steps0)
            .put("steps_end_status", healthStatus)
            .put("session_steps_direct", directSteps < 0 ? JSONObject.NULL : directSteps)
            .put("session_steps_direct_status", directStepStatus)
            .put("session_steps_direct_samples", directStepSamples)
            .put("google_fit_comparison", fit)
            .put("gps", new JSONObject().put("samples", points.size()).put("accepted", accepted).put("rejected", points.size()-accepted)
                .put("rejection_reasons", reasons).put("accuracy_mean_m", points.isEmpty()?JSONObject.NULL:accuracySum/points.size()).put("accuracy_max_m", accuracyMax))
            .put("resources", new JSONObject().put("battery_start_pct", p.getInt(s.id + ".battery", -1)).put("battery_end_pct", battery(c))
                .put("wall_elapsed_ms", monotonicDelta(elapsed0, android.os.SystemClock.elapsedRealtime()))
                .put("process_cpu_ms", monotonicDelta(cpu0, Process.getElapsedCpuTime())).put("process_pss_kb", Debug.getPss())
                .put("device_available_memory_bytes", memory.availMem).put("network_rx_bytes", delta(rx0, TrafficStats.getUidRxBytes(Process.myUid())))
                .put("network_tx_bytes", delta(tx0, TrafficStats.getUidTxBytes(Process.myUid()))))
            .put("device", new JSONObject().put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL).put("android_api", Build.VERSION.SDK_INT)
                .put("app_version", appVersion(c))).put("points", samples);
    }

    private static Object delta(long a, long b) { return a < 0 || b < 0 ? JSONObject.NULL : Math.max(0, b-a); }
    private static Object monotonicDelta(long a, long b) { return a <= 0 || b < a ? JSONObject.NULL : b-a; }
    private static int battery(Context c) { return ((BatteryManager)c.getSystemService(Context.BATTERY_SERVICE)).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY); }
    private static String appVersion(Context c) {
        try { return c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName; }
        catch (Exception ignored) { return "unknown"; }
    }
    private static Uri tree(Context c) { String value=c.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString(TREE_URI,null); return value==null?null:Uri.parse(value); }
    private static boolean canReadFolder(Context c, Uri tree) {
        Uri directory = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        try (Cursor cursor = c.getContentResolver().query(directory,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID}, null, null, null)) {
            return cursor != null && cursor.moveToFirst();
        }
    }
    private static void writeFile(Context c, String name, String mime, String text) throws Exception {
        Uri tree=tree(c); if(tree==null)throw new IllegalStateException("folder missing");
        Uri dir = managedDirectory(c, tree, DriveFolderLayout.folderFor(name));
        String directoryId = DocumentsContract.getDocumentId(dir);
        Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        Uri file = null;
        try (Cursor cursor = c.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME},
            null, null, null)) {
            if (cursor != null) while (cursor.moveToNext()) {
                if (name.equals(cursor.getString(1))) {
                    file = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0));
                    break;
                }
            }
        }
        if (file == null) file=DocumentsContract.createDocument(c.getContentResolver(),dir,mime,name);
        if(file==null)throw new IllegalStateException("create failed");
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        try (ParcelFileDescriptor descriptor = c.getContentResolver().openFileDescriptor(file, "rwt")) {
            if (descriptor == null) throw new IllegalStateException("open failed");
            try (FileOutputStream out = new FileOutputStream(descriptor.getFileDescriptor())) {
                out.write(bytes);
                out.flush();
                descriptor.getFileDescriptor().sync();
            }
        }
        Long observedSize = null;
        try (Cursor cursor = c.getContentResolver().query(file,
            new String[] {DocumentsContract.Document.COLUMN_SIZE}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0))
                observedSize = cursor.getLong(0);
        }
        if (!DriveWriteVerification.matchesSize(bytes.length, observedSize))
            throw new IOException("provider size mismatch");
    }

    private static void writeNewFile(Context c, String name, String mime, String text) throws Exception {
        Uri tree = tree(c); if (tree == null) throw new IllegalStateException("folder missing");
        Uri dir = managedDirectory(c, tree, DriveFolderLayout.folderFor(name));
        String directoryId = DocumentsContract.getDocumentId(dir);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        try (Cursor cursor = c.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
            if (cursor != null) while (cursor.moveToNext())
                if (name.equals(cursor.getString(0))) return;
        }
        Uri file = DocumentsContract.createDocument(c.getContentResolver(), dir, mime, name);
        if (file == null) throw new IllegalStateException("create failed");
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        try (ParcelFileDescriptor descriptor = c.getContentResolver().openFileDescriptor(file, "rwt")) {
            if (descriptor == null) throw new IllegalStateException("open failed");
            try (FileOutputStream out = new FileOutputStream(descriptor.getFileDescriptor())) {
                out.write(bytes); out.flush(); descriptor.getFileDescriptor().sync();
            }
        }
    }

    static void writeDailyDiagnostics(Context context, String name, String text) throws Exception {
        writeNewFile(context, name, "application/x-ndjson", text);
        pruneDailyDiagnostics(context, 15);
    }

    static void writeUnifiedDiagnostics(Context context, String name, String text) throws Exception {
        writeNewFile(context, name, "application/json", text);
        pruneManagedFiles(context, "unified_diagnostics_", ".json",
            UnifiedDiagnosticReport.RETAIN_FILES);
    }

    static ExportResult writeIntensiveDiagnosticChunk(Context context, java.io.File chunk) {
        if (!isConfigured(context)) return new ExportResult(false, false, "not_configured");
        try {
            String text = new String(java.nio.file.Files.readAllBytes(chunk.toPath()),
                StandardCharsets.UTF_8);
            writeNewFile(context, chunk.getName(), "application/x-ndjson", text);
            return new ExportResult(true, true, "ok");
        } catch (Exception error) {
            return new ExportResult(true, false,
                "intensive_chunk_failed_" + error.getClass().getSimpleName());
        }
    }

    private static void pruneDailyDiagnostics(Context context, int keep) throws Exception {
        pruneManagedFiles(context, DiagnosticRetentionPolicy.PREFIX,
            DiagnosticRetentionPolicy.SUFFIX, keep);
    }

    private static void pruneManagedFiles(Context context, String prefix, String suffix,
                                          int keep) throws Exception {
        Uri tree = tree(context); if (tree == null) throw new IllegalStateException("folder missing");
        Uri dir = managedDirectory(context, tree, DriveFolderLayout.APP_DIAGNOSTICS);
        String directoryId = DocumentsContract.getDocumentId(dir);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directoryId);
        List<DiagnosticRetentionPolicy.Entry> entries = new ArrayList<>();
        try (Cursor cursor = context.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
            if (cursor != null) while (cursor.moveToNext()) {
                String name = cursor.getString(1);
                if (name != null && name.startsWith(prefix) && name.endsWith(suffix))
                    entries.add(new DiagnosticRetentionPolicy.Entry(cursor.getString(0), name));
            }
        }
        for (DiagnosticRetentionPolicy.Entry entry :
            entriesToDelete(entries, keep)) {
            Uri document = DocumentsContract.buildDocumentUriUsingTree(tree, entry.id());
            DocumentsContract.deleteDocument(context.getContentResolver(), document);
        }
    }

    private static List<DiagnosticRetentionPolicy.Entry> entriesToDelete(
        List<DiagnosticRetentionPolicy.Entry> entries, int keep) {
        entries.sort(java.util.Comparator.comparing(DiagnosticRetentionPolicy.Entry::name).reversed());
        if (entries.size() <= keep) return java.util.List.of();
        return new java.util.ArrayList<>(entries.subList(keep, entries.size()));
    }

    private static synchronized Uri managedDirectory(Context context, Uri tree,
                                                       String folderName) throws Exception {
        String rootId = DocumentsContract.getTreeDocumentId(tree);
        Uri root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId);
        if (folderName == null) return root;
        String preferenceKey = DIRECTORY_ID_PREFIX + DriveFolderLayout.preferenceKey(folderName);
        android.content.SharedPreferences preferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (tree.toString().equals(preferences.getString(DIRECTORY_TREE_URI, null))) {
            String cachedId = preferences.getString(preferenceKey, null);
            if (cachedId != null) {
                Uri cached = DocumentsContract.buildDocumentUriUsingTree(tree, cachedId);
                if (canReadDocument(context, cached)) return cached;
                preferences.edit().remove(preferenceKey).apply();
            }
        }
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId);
        try (Cursor cursor = context.getContentResolver().query(children,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE}, null, null, null)) {
            if (cursor != null) while (cursor.moveToNext()) {
                if (folderName.equals(cursor.getString(1))
                    && DocumentsContract.Document.MIME_TYPE_DIR.equals(cursor.getString(2))) {
                    String documentId = cursor.getString(0);
                    cacheManagedDirectory(preferences, tree, preferenceKey, documentId);
                    return DocumentsContract.buildDocumentUriUsingTree(tree, documentId);
                }
            }
        }
        Uri created = DocumentsContract.createDocument(context.getContentResolver(), root,
            DocumentsContract.Document.MIME_TYPE_DIR, folderName);
        if (created == null) throw new IOException("Drive directory creation failed");
        cacheManagedDirectory(preferences, tree, preferenceKey,
            DocumentsContract.getDocumentId(created));
        return created;
    }

    private static void cacheManagedDirectory(android.content.SharedPreferences preferences,
                                               Uri tree, String preferenceKey,
                                               String documentId) {
        preferences.edit()
            .putString(DIRECTORY_TREE_URI, tree.toString())
            .putString(preferenceKey, documentId)
            .apply();
    }

    private static boolean canReadDocument(Context context, Uri document) {
        try (Cursor cursor = context.getContentResolver().query(document,
            new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID}, null, null, null)) {
            return cursor != null && cursor.moveToFirst();
        } catch (RuntimeException ignored) {
            return false;
        }
    }
}
