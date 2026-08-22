package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.pm.PackageInfo;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

/** Compact remote-observation report. Raw health timelines and Todo content are excluded. */
final class UnifiedDiagnosticReport {
    static final int SCHEMA_VERSION = 3;
    static final int RETAIN_FILES = 15;
    private static final long THREE_HOURS_MS = 3L * 60 * 60 * 1000;
    private static final long DAY_MS = 24L * 60 * 60 * 1000;

    private UnifiedDiagnosticReport() {}

    record BipSummary(int sampleCount, long expectedMinuteCount, double minuteCoverageRatio,
                      long steps, int heartRateSampleCount, Integer heartRateMinBpm,
                      Integer heartRateMaxBpm, Double heartRateMeanBpm, Long firstSampleAtMillis,
                      Long lastSampleAtMillis, Long lastSampleAgeMillis) {}

    static String fileName(long observedAtMillis, ZoneId zone) {
        String bucket = Instant.ofEpochMilli(observedAtMillis).atZone(zone)
            .format(DateTimeFormatter.ofPattern("yyyy-MM-dd_HH"));
        return "unified_diagnostics_" + bucket + ".json";
    }

    static JSONObject create(Context context, long observedAtMillis) throws Exception {
        RunDao dao = RunDatabase.get(context).runs();
        IntensiveDiagnosticExperiment.State intensive = IntensiveDiagnosticExperiment.state(context);
        return new JSONObject().put("schema_version", SCHEMA_VERSION)
            .put("kind", "unified_remote_diagnostics")
            .put("observed_at_ms", observedAtMillis)
            .put("zone_id", ZoneId.systemDefault().getId())
            .put("app", app(context))
            .put("phone_and_fit", object(PassiveMovementDebugState.values(context)))
            .put("bip_u", new JSONObject()
                .put("last_sync", object(BipUSyncDebugState.values(context)))
                .put("last_3_hours", bipWindow(dao.bipUSamples(observedAtMillis - THREE_HOURS_MS,
                    observedAtMillis), observedAtMillis, THREE_HOURS_MS))
                .put("last_24_hours", bipWindow(dao.bipUSamples(observedAtMillis - DAY_MS,
                    observedAtMillis), observedAtMillis, DAY_MS)))
            .put("intensive_experiment", new JSONObject()
                .put("active", intensive.active(observedAtMillis))
                .put("started_at_ms", nullable(intensive.startedAtMillis()))
                .put("end_at_ms", nullable(intensive.endAtMillis()))
                .put("pending_upload_chunks", IntensiveDiagnosticStore.pendingChunks(context).size())
                .put("coverage", object(IntensiveDiagnosticDebugState.values(context))))
            .put("diagnostic_upload", object(DiagnosticUploadDebugState.values(context)))
            .put("app_diagnostic_log", diagnosticFiles(context))
            .put("privacy", new JSONObject().put("todo_content_recorded", false)
                .put("coordinates_recorded", false).put("mac_recorded", false)
                .put("auth_key_recorded", false).put("raw_health_timeline_exported", false));
    }

    static JSONObject bipWindow(List<BipUActivitySample> samples, long observedAtMillis,
                                long windowMillis) throws Exception {
        BipSummary summary = summarizeBipWindow(samples, observedAtMillis, windowMillis);
        return new JSONObject().put("sample_count", summary.sampleCount())
            .put("expected_minute_count", summary.expectedMinuteCount())
            .put("minute_coverage_ratio", summary.minuteCoverageRatio())
            .put("steps", summary.steps()).put("heart_rate_sample_count", summary.heartRateSampleCount())
            .put("heart_rate_min_bpm", nullable(summary.heartRateMinBpm()))
            .put("heart_rate_max_bpm", nullable(summary.heartRateMaxBpm()))
            .put("heart_rate_mean_bpm", nullable(summary.heartRateMeanBpm()))
            .put("first_sample_at_ms", nullable(summary.firstSampleAtMillis()))
            .put("last_sample_at_ms", nullable(summary.lastSampleAtMillis()))
            .put("last_sample_age_ms", nullable(summary.lastSampleAgeMillis()));
    }

    static BipSummary summarizeBipWindow(List<BipUActivitySample> samples, long observedAtMillis,
                                         long windowMillis) {
        long steps = 0, heartTotal = 0, first = 0, last = 0;
        int heartCount = 0, heartMin = Integer.MAX_VALUE, heartMax = Integer.MIN_VALUE;
        for (BipUActivitySample sample : samples) {
            if (first == 0 || sample.timestampMillis < first) first = sample.timestampMillis;
            if (sample.timestampMillis > last) last = sample.timestampMillis;
            steps += Math.max(0, sample.steps);
            if (sample.heartRate > 0) {
                heartCount++; heartTotal += sample.heartRate;
                heartMin = Math.min(heartMin, sample.heartRate);
                heartMax = Math.max(heartMax, sample.heartRate);
            }
        }
        long expectedMinutes = Math.max(1, windowMillis / 60_000L);
        return new BipSummary(samples.size(), expectedMinutes,
            Math.min(1.0, samples.size() / (double) expectedMinutes), steps, heartCount,
            heartCount == 0 ? null : heartMin, heartCount == 0 ? null : heartMax,
            heartCount == 0 ? null : heartTotal / (double) heartCount,
            first == 0 ? null : first, last == 0 ? null : last,
            last == 0 ? null : Math.max(0, observedAtMillis - last));
    }

    private static JSONObject app(Context context) throws Exception {
        PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
        return new JSONObject().put("version_name", info.versionName)
            .put("version_code", info.getLongVersionCode()).put("android_api", android.os.Build.VERSION.SDK_INT);
    }

    private static JSONObject diagnosticFiles(Context context) throws Exception {
        JSONArray files = new JSONArray();
        addFile(files, new File(context.getFilesDir(), "diagnostics.jsonl.1"));
        addFile(files, new File(context.getFilesDir(), "diagnostics.jsonl"));
        return new JSONObject().put("files", files);
    }

    private static void addFile(JSONArray output, File file) throws Exception {
        if (!file.isFile()) return;
        long lines = 0;
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[8192]; int read;
            while ((read = input.read(buffer)) != -1)
                for (int i = 0; i < read; i++) if (buffer[i] == '\n') lines++;
        }
        output.put(new JSONObject().put("name", file.getName()).put("bytes", file.length())
            .put("lines", lines).put("last_modified_ms", file.lastModified()));
    }

    private static JSONObject object(Map<String, Object> values) throws Exception {
        JSONObject result = new JSONObject();
        for (Map.Entry<String, Object> entry : values.entrySet())
            result.put(entry.getKey(), entry.getValue() == null ? JSONObject.NULL : entry.getValue());
        return result;
    }

    private static Object nullable(long value) { return value <= 0 ? JSONObject.NULL : value; }
    private static Object nullable(Object value) { return value == null ? JSONObject.NULL : value; }
}
