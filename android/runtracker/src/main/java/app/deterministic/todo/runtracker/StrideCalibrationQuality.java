package app.deterministic.todo.runtracker;

import java.util.List;

/** Determines whether a labelled session is pure enough to calibrate its stride profile. */
final class StrideCalibrationQuality {
    static final long BUCKET_MILLIS = 30_000;
    static final double RUNNING_CADENCE_SPM = 135.0;
    static final double MIN_EXPECTED_SHARE = 0.80;

    record Assessment(long observedSteps, long walkingSteps, long runningSteps,
                      double expectedShare, boolean pure) {}

    private StrideCalibrationQuality() {}

    static Assessment assess(String type, DirectStepTimeline timeline, long startedAt, long endedAt) {
        List<DirectStepTimeline.Sample> samples = timeline == null ? List.of() : timeline.snapshot();
        if (samples.size() < 2 || endedAt <= startedAt) return new Assessment(0, 0, 0, 0, false);
        int index = 0;
        long current = samples.get(0).steps();
        while (index + 1 < samples.size() && samples.get(index + 1).timeMillis() <= startedAt)
            current = samples.get(++index).steps();
        long last = current;
        long walking = 0;
        long running = 0;
        for (long bucketStart = startedAt; bucketStart < endedAt; bucketStart += BUCKET_MILLIS) {
            long bucketEnd = Math.min(endedAt, bucketStart + BUCKET_MILLIS);
            while (index + 1 < samples.size() && samples.get(index + 1).timeMillis() <= bucketEnd)
                current = samples.get(++index).steps();
            long increment = Math.max(0, current - last);
            last = current;
            if (increment == 0) continue;
            double cadence = increment * 60_000.0 / Math.max(1, bucketEnd - bucketStart);
            if (cadence >= RUNNING_CADENCE_SPM) running += increment;
            else walking += increment;
        }
        long observed = walking + running;
        long expected = "running".equals(type) ? running : walking;
        double share = observed == 0 ? 0 : expected / (double) observed;
        return new Assessment(observed, walking, running, share,
            observed > 0 && share >= MIN_EXPECTED_SHARE);
    }
}
