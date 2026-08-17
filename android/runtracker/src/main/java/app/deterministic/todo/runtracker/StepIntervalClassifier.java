package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Allocates a coarse step record across the activity states that overlap it. */
final class StepIntervalClassifier {
    private static final double MIN_EXCLUDED_SHARE = 0.80;

    record Result(long walking, long running, long unknown, long vehicle,
                  long bicycle, long stillConflict) {
        long excluded() { return vehicle + bicycle; }
        long total() { return walking + running + unknown + vehicle + bicycle + stillConflict; }
    }

    private StepIntervalClassifier() {}

    static Result classify(long startMillis, long endMillis, long steps,
                           List<ActivityTimeline.Event> timeline) {
        if (steps <= 0) return new Result(0, 0, 0, 0, 0, 0);
        if (endMillis <= startMillis) return new Result(0, 0, steps, 0, 0, 0);

        long[] durations = new long[6];
        List<Long> boundaries = new ArrayList<>();
        boundaries.add(startMillis);
        for (ActivityTimeline.Event event : timeline) {
            if (event.atMillis() > startMillis && event.atMillis() < endMillis) {
                boundaries.add(event.atMillis());
            }
        }
        boundaries.add(endMillis);
        boundaries.sort(Comparator.naturalOrder());

        for (int i = 0; i < boundaries.size() - 1; i++) {
            long segmentStart = boundaries.get(i);
            long duration = boundaries.get(i + 1) - segmentStart;
            durations[bucket(ActivityTimeline.at(timeline, segmentStart))] += duration;
        }

        long totalDuration = endMillis - startMillis;
        double excludedShare = (durations[3] + durations[4]) / (double) totalDuration;
        if (excludedShare > 0 && excludedShare < MIN_EXCLUDED_SHARE) {
            durations[2] += durations[3] + durations[4];
            durations[3] = 0;
            durations[4] = 0;
        }

        long[] allocated = allocateExactly(steps, durations, totalDuration);
        return new Result(allocated[0], allocated[1], allocated[2], allocated[3],
            allocated[4], allocated[5]);
    }

    private static int bucket(String activity) {
        return switch (activity) {
            case ActivityTimeline.WALKING -> 0;
            case ActivityTimeline.RUNNING -> 1;
            case ActivityTimeline.VEHICLE -> 3;
            case ActivityTimeline.BICYCLE -> 4;
            case ActivityTimeline.STILL -> 5;
            default -> 2;
        };
    }

    private static long[] allocateExactly(long steps, long[] durations, long totalDuration) {
        long[] result = new long[durations.length];
        double[] remainders = new double[durations.length];
        long allocated = 0;
        for (int i = 0; i < durations.length; i++) {
            double exact = steps * (durations[i] / (double) totalDuration);
            result[i] = (long) Math.floor(exact);
            remainders[i] = exact - result[i];
            allocated += result[i];
        }
        while (allocated < steps) {
            int best = 0;
            for (int i = 1; i < remainders.length; i++) {
                if (remainders[i] > remainders[best]) best = i;
            }
            result[best]++;
            remainders[best] = -1;
            allocated++;
        }
        return result;
    }
}
