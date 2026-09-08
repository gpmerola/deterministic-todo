package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Observed GPS delivery cadence; distinct from the requested Android interval. */
final class GpsSamplingStats {
    record Summary(int intervalCount, Double meanMillis, Long medianMillis,
                   Long p95Millis, Long maximumMillis) {}

    private GpsSamplingStats() {}

    static Summary summarize(List<TrackPoint> points) {
        ArrayList<Long> intervals = new ArrayList<>();
        long previous = 0; double total = 0;
        for (TrackPoint point : points) {
            if (previous > 0 && point.timestampMillis > previous) {
                long interval = point.timestampMillis - previous;
                intervals.add(interval); total += interval;
            }
            if (point.timestampMillis > previous) previous = point.timestampMillis;
        }
        if (intervals.isEmpty()) return new Summary(0, null, null, null, null);
        Collections.sort(intervals);
        return new Summary(intervals.size(), total / intervals.size(),
            percentile(intervals, 0.50), percentile(intervals, 0.95),
            intervals.get(intervals.size() - 1));
    }

    private static long percentile(List<Long> sorted, double percentile) {
        int index = (int) Math.ceil(percentile * sorted.size()) - 1;
        return sorted.get(Math.max(0, Math.min(sorted.size() - 1, index)));
    }
}
