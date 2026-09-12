package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

/** Explicit, bounded local observation. Missing minutes never become measured zeroes. */
final class LocalStepIntervalReport {
    static final long MINUTE = 60_000;
    record Range(long start, long end) {
        Range {
            if (start < 0 || end <= start || end - start > 60 * MINUTE
                || end > Long.MAX_VALUE - MINUTE)
                throw new IllegalArgumentException("Expected UTC milliseconds and 0 < interval <= 1 hour");
        }
        long firstMinute() { return start / MINUTE * MINUTE; }
    }
    record Row(long minuteStart, long overlapMillis, LocalStepMinute sample,
               Long stepsLower, Long stepsUpper, Double proratedSteps, Double estimatedMeters) {}

    static List<Row> build(Range range, List<LocalStepMinute> samples,
                           List<ActivityTimeline.Event> timeline, MovementProfile profile) {
        var byMinute = new HashMap<Long, LocalStepMinute>();
        for (var sample : samples) byMinute.put(sample.startMillis, sample);
        var rows = new ArrayList<Row>();
        for (long at = range.firstMinute(); at < range.end(); at += MINUTE) {
            long overlap = Math.min(at + MINUTE, range.end()) - Math.max(at, range.start());
            var sample = byMinute.get(at);
            if (sample == null) {
                rows.add(new Row(at, overlap, null, null, null, null, null));
                continue;
            }
            var estimate = LocalDailyMovementModel.calculate(List.of(sample), timeline, List.of(),
                range.start(), range.end(), 0, profile);
            rows.add(new Row(at, overlap, sample, overlap == MINUTE ? sample.steps : 0L,
                sample.steps, sample.steps * (overlap / (double) MINUTE), estimate.meters()));
        }
        return rows;
    }
}
