package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.List;

/** Session-scoped UTC alignment of phone, Google Fit and optional Bip U evidence. */
final class SessionThreeWayReport {
    static final int SCHEMA_VERSION = 1;
    static final long WINDOW_MILLIS = 60_000L;

    record FitSnapshot(Long steps, Double distanceMeters, Double activeCalories,
                       long observedAtMillis, String status) {}

    private SessionThreeWayReport() {}

    static JSONObject create(Context context, RunSession session, long observedAtMillis)
        throws Exception {
        RunDao dao = RunDatabase.get(context).runs();
        SharedPreferences p = context.getSharedPreferences(
            DriveTestExportManager.PREFS, Context.MODE_PRIVATE);
        FitSnapshot fit = new FitSnapshot(
            p.contains(session.id + ".fit_steps") ? p.getLong(session.id + ".fit_steps", 0) : null,
            p.contains(session.id + ".fit_distance_m")
                ? (double) p.getFloat(session.id + ".fit_distance_m", 0) : null,
            p.contains(session.id + ".fit_active_calories")
                ? (double) p.getFloat(session.id + ".fit_active_calories", 0) : null,
            p.getLong(session.id + ".fit_observed_at", 0),
            p.getString(session.id + ".comparison_status", "not_compared"));
        long end = session.endedAtMillis == null ? observedAtMillis : session.endedAtMillis;
        return build(session, dao.points(session.id),
            DriveTestExportManager.directStepTimeline(context, session.id),
            dao.bipUSamples(session.startedAtMillis, end), fit, observedAtMillis);
    }

    static JSONObject build(RunSession session, List<TrackPoint> points,
                            DirectStepTimeline phoneSteps, List<BipUActivitySample> bipSamples,
                            FitSnapshot fit, long observedAtMillis) throws Exception {
        long end = session.endedAtMillis == null ? observedAtMillis : session.endedAtMillis;
        int windows = (int) Math.max(1,
            (end - session.startedAtMillis + WINDOW_MILLIS - 1) / WINDOW_MILLIS);
        long[] todoSteps = new long[windows];
        double[] todoDistance = new double[windows];
        long[] bipSteps = new long[windows];
        int[] bipCount = new int[windows], heartCount = new int[windows], heartTotal = new int[windows];
        int[] heartMin = new int[windows], heartMax = new int[windows];
        java.util.Arrays.fill(heartMin, Integer.MAX_VALUE);

        long lastSteps = 0;
        boolean haveSteps = false;
        for (DirectStepTimeline.Sample sample : phoneSteps.snapshot()) {
            if (sample.timeMillis() < session.startedAtMillis) {
                lastSteps = sample.steps(); haveSteps = true; continue;
            }
            if (sample.timeMillis() > end) break;
            if (!haveSteps) { lastSteps = sample.steps(); haveSteps = true; continue; }
            long increment = Math.max(0, sample.steps() - lastSteps);
            lastSteps = sample.steps();
            todoSteps[index(session.startedAtMillis, sample.timeMillis(), windows)] += increment;
        }

        double lastDistance = 0;
        for (TrackPoint point : points) {
            if (point.timestampMillis < session.startedAtMillis || point.timestampMillis >= end) continue;
            double increment = Math.max(0, point.accumulatedDistanceMeters - lastDistance);
            lastDistance = Math.max(lastDistance, point.accumulatedDistanceMeters);
            todoDistance[index(session.startedAtMillis, point.timestampMillis, windows)] += increment;
        }

        long bipTotalSteps = 0;
        int bipHeartCount = 0, bipHeartTotal = 0, bipHeartMin = Integer.MAX_VALUE,
            bipHeartMax = Integer.MIN_VALUE;
        for (BipUActivitySample sample : bipSamples) {
            int bucket = index(session.startedAtMillis, sample.timestampMillis, windows);
            int safeSteps = Math.max(0, sample.steps);
            bipSteps[bucket] += safeSteps; bipTotalSteps += safeSteps; bipCount[bucket]++;
            if (sample.heartRate > 0 && sample.heartRate < 255) {
                heartCount[bucket]++; heartTotal[bucket] += sample.heartRate;
                heartMin[bucket] = Math.min(heartMin[bucket], sample.heartRate);
                heartMax[bucket] = Math.max(heartMax[bucket], sample.heartRate);
                bipHeartCount++; bipHeartTotal += sample.heartRate;
                bipHeartMin = Math.min(bipHeartMin, sample.heartRate);
                bipHeartMax = Math.max(bipHeartMax, sample.heartRate);
            }
        }

        long todoTotalSteps = 0; double todoTotalDistance = 0;
        JSONArray timeline = new JSONArray();
        for (int i = 0; i < windows; i++) {
            todoTotalSteps += todoSteps[i]; todoTotalDistance += todoDistance[i];
            long start = session.startedAtMillis + i * WINDOW_MILLIS;
            timeline.put(new JSONObject().put("window_index", i)
                .put("started_at_ms", start).put("ended_at_ms", Math.min(end, start + WINDOW_MILLIS))
                .put("todo_test", new JSONObject().put("steps", todoSteps[i])
                    .put("gps_distance_m", todoDistance[i]))
                .put("google_fit", new JSONObject().put("resolution", "session_aggregate_only")
                    .put("steps", JSONObject.NULL).put("distance_m", JSONObject.NULL))
                .put("bip_u", new JSONObject().put("available", bipCount[i] > 0)
                    .put("sample_count", bipCount[i]).put("steps", bipSteps[i])
                    .put("heart_rate_sample_count", heartCount[i])
                    .put("heart_rate_min_bpm", heartCount[i] == 0 ? JSONObject.NULL : heartMin[i])
                    .put("heart_rate_max_bpm", heartCount[i] == 0 ? JSONObject.NULL : heartMax[i])
                    .put("heart_rate_mean_bpm", heartCount[i] == 0 ? JSONObject.NULL
                        : heartTotal[i] / (double) heartCount[i])));
        }

        JSONObject totals = new JSONObject()
            .put("todo_test", new JSONObject().put("steps", todoTotalSteps)
                .put("gps_distance_m", todoTotalDistance))
            .put("google_fit", new JSONObject().put("status", fit.status())
                .put("observed_at_ms", nullable(fit.observedAtMillis()))
                .put("steps", nullable(fit.steps())).put("distance_m", nullable(fit.distanceMeters()))
                .put("active_calories", nullable(fit.activeCalories())))
            .put("bip_u", new JSONObject().put("available", !bipSamples.isEmpty())
                .put("sample_count", bipSamples.size()).put("steps", bipTotalSteps)
                .put("heart_rate_sample_count", bipHeartCount)
                .put("heart_rate_min_bpm", bipHeartCount == 0 ? JSONObject.NULL : bipHeartMin)
                .put("heart_rate_max_bpm", bipHeartCount == 0 ? JSONObject.NULL : bipHeartMax)
                .put("heart_rate_mean_bpm", bipHeartCount == 0 ? JSONObject.NULL
                    : bipHeartTotal / (double) bipHeartCount));

        JSONObject comparisons = new JSONObject()
            .put("steps", new JSONObject()
                .put("todo_vs_fit", metric(todoTotalSteps, fit.steps()))
                .put("todo_vs_bip", metric(todoTotalSteps,
                    bipSamples.isEmpty() ? null : bipTotalSteps))
                .put("bip_vs_fit", metric(bipSamples.isEmpty() ? null : bipTotalSteps, fit.steps())))
            .put("distance_m", new JSONObject()
                .put("todo_vs_fit", metric(todoTotalDistance, fit.distanceMeters()))
                .put("bip_available", false));

        JSONArray bipTimeline = new JSONArray();
        for (BipUActivitySample sample : bipSamples) {
            bipTimeline.put(new JSONObject().put("timestamp_ms", sample.timestampMillis)
                .put("source", sample.source).put("imported_at_ms", sample.importedAtMillis)
                .put("steps", sample.steps).put("heart_rate_bpm",
                    sample.heartRate > 0 && sample.heartRate < 255
                        ? sample.heartRate : JSONObject.NULL)
                .put("raw_kind", sample.rawKind).put("raw_intensity", sample.rawIntensity)
                .put("raw_sleep", sample.sleep).put("raw_deep_sleep", sample.deepSleep)
                .put("raw_rem_sleep", sample.remSleep).put("unknown_1", sample.unknown1));
        }

        return new JSONObject().put("schema_version", SCHEMA_VERSION)
            .put("kind", "movement_session_three_way")
            .put("session_id", session.id).put("activity", session.activityType)
            .put("started_at_ms", session.startedAtMillis).put("ended_at_ms", end)
            .put("observed_at_ms", observedAtMillis).put("window_millis", WINDOW_MILLIS)
            .put("alignment", new JSONObject().put("time_basis", "UTC_epoch_millis")
                .put("bip_native_resolution_millis", 60_000)
                .put("google_fit_resolution", "session_aggregate")
                .put("clock_offset_correction_applied", false))
            .put("coverage", new JSONObject().put("window_count", windows)
                .put("bip_sample_count", bipSamples.size())
                .put("bip_window_coverage_ratio", Math.min(1.0, bipSamples.size() / (double) windows))
                .put("fit_session_aggregate_available", fit.steps() != null || fit.distanceMeters() != null))
            .put("totals", totals).put("comparisons", comparisons).put("timeline", timeline)
            .put("bip_u_native_samples", bipTimeline)
            .put("privacy", new JSONObject().put("coordinates_recorded", false)
                .put("bip_health_timeline_recorded", true).put("mac_recorded", false)
                .put("auth_key_recorded", false).put("todo_content_recorded", false));
    }

    private static int index(long start, long time, int count) {
        return Math.max(0, Math.min(count - 1, (int) ((time - start) / WINDOW_MILLIS)));
    }

    private static JSONObject metric(Number left, Number right) throws Exception {
        if (left == null || right == null) return new JSONObject().put("available", false);
        double delta = left.doubleValue() - right.doubleValue();
        return new JSONObject().put("available", true).put("left", left).put("right", right)
            .put("absolute_delta", delta).put("percent_delta_vs_right",
                right.doubleValue() == 0 ? JSONObject.NULL : delta * 100 / right.doubleValue());
    }

    private static Object nullable(Object value) { return value == null ? JSONObject.NULL : value; }
    private static Object nullable(long value) { return value <= 0 ? JSONObject.NULL : value; }
}
