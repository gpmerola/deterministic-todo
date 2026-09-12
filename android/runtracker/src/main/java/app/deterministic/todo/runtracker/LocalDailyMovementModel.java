package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Disjoint UTC intervals; GPS replaces the overlapping step estimate, never adds to it. */
final class LocalDailyMovementModel {
    record GpsSegment(long start, long end, double meters, String activity) {}
    record Result(double meters, double activeCalories, double gpsMeters,
                  long walkingSteps, long runningSteps, long unknownSteps) {}

    static Result calculate(List<LocalStepMinute> minutes, List<ActivityTimeline.Event> timeline,
                            List<GpsSegment> gps, long start, long end, long legacySteps,
                            MovementProfile profile) {
        var segments = new ArrayList<GpsSegment>();
        long previousEnd = Long.MIN_VALUE;
        var sorted = new ArrayList<>(gps);
        sorted.sort(Comparator.comparingLong(GpsSegment::start).thenComparingLong(GpsSegment::end));
        for (var segment : sorted) {
            if (segment.end <= segment.start || !Double.isFinite(segment.meters) || segment.meters < 0
                || segment.start < previousEnd) continue; // Duplicate/overlapping GPS evidence is not summed.
            long from = Math.max(start, segment.start), to = Math.min(end, segment.end);
            if (from >= to) continue;
            segments.add(new GpsSegment(from, to, segment.meters * (to - from)
                / (segment.end - segment.start), segment.activity));
            previousEnd = segment.end;
        }
        double meters = Math.max(0, legacySteps) * profile.walkingStride();
        double calories = meters / 1000 * profile.weightKg() * .5;
        double gpsMeters = 0;
        long walking = 0, running = 0, unknown = Math.max(0, legacySteps);
        for (var minute : minutes) {
            long from = Math.max(start, minute.startMillis);
            long to = Math.min(end, minute.startMillis + LocalStepImportPolicy.MINUTE);
            if (from >= to) continue;
            var classified = StepIntervalClassifier.classify(minute.startMillis,
                minute.startMillis + LocalStepImportPolicy.MINUTE, minute.steps, timeline);
            walking += classified.walking();
            running += classified.running();
            unknown += classified.unknown() + classified.stillConflict();
            var estimate = MixedMovementEstimate.calculate(classified.walking(), classified.running(),
                classified.unknown() + classified.stillConflict(), classified.excluded(),
                profile.walkingStride(), profile.runningStride(), profile.weightKg());
            long covered = 0;
            for (var segment : segments)
                covered += Math.max(0, Math.min(to, segment.end) - Math.max(from, segment.start));
            double uncoveredShare = (to - from - covered) / (double) LocalStepImportPolicy.MINUTE;
            meters += estimate.distanceMeters() * uncoveredShare;
            calories += estimate.activeCalories() * uncoveredShare;
        }
        for (var segment : segments) {
            meters += segment.meters;
            gpsMeters += segment.meters;
            calories += segment.meters / 1000 * profile.weightKg()
                * ("run".equals(segment.activity) ? 1 : .5);
        }
        return new Result(meters, calories, gpsMeters, walking, running, unknown);
    }
}
