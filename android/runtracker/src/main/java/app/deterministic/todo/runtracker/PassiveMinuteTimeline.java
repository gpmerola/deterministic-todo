package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Minute-aligned, coordinate-free passive evidence reconstructed from Health Connect records. */
public final class PassiveMinuteTimeline {
    static final long MINUTE_MILLIS = 60_000L;

    public record Minute(long startMillis, long endMillis, long todoSteps, long fitStepsRaw,
                  double fitDistanceMeters, long walkingSteps, long runningSteps,
                  long unknownSteps, long vehicleSteps, long bicycleSteps,
                  long stillConflictSteps) {}

    private static final class MutableMinute {
        final long start;
        long fitSteps;
        double fitDistance;
        final long[] classified = new long[6];

        MutableMinute(long start) { this.start = start; }
        long rawSteps() {
            long total = 0;
            for (long value : classified) total += value;
            return total;
        }
    }

    static final class Builder {
        private final Map<Long, MutableMinute> minutes = new LinkedHashMap<>();

        void addSteps(long startMillis, long endMillis, long steps, boolean googleFit,
                      List<ActivityTimeline.Event> activities) {
            if (steps <= 0 || endMillis <= startMillis) return;
            List<Slice> slices = slices(startMillis, endMillis);
            long[] allocated = allocateExactly(steps, slices, endMillis - startMillis);
            for (int i = 0; i < slices.size(); i++) {
                if (allocated[i] == 0) continue;
                Slice slice = slices.get(i);
                MutableMinute minute = minute(slice.minuteStart);
                StepIntervalClassifier.Result classified = StepIntervalClassifier.classify(
                    slice.start, slice.end, allocated[i], activities);
                minute.classified[0] += classified.walking();
                minute.classified[1] += classified.running();
                minute.classified[2] += classified.unknown();
                minute.classified[3] += classified.vehicle();
                minute.classified[4] += classified.bicycle();
                minute.classified[5] += classified.stillConflict();
                if (googleFit) minute.fitSteps += allocated[i];
            }
        }

        void addFitDistance(long startMillis, long endMillis, double meters) {
            if (!Double.isFinite(meters) || meters <= 0 || endMillis <= startMillis) return;
            List<Slice> slices = slices(startMillis, endMillis);
            long duration = endMillis - startMillis;
            for (Slice slice : slices) {
                minute(slice.minuteStart).fitDistance += meters
                    * (slice.end - slice.start) / (double) duration;
            }
        }

        List<Minute> build(long aggregateSteps) {
            List<MutableMinute> ordered = new ArrayList<>(minutes.values());
            ordered.sort(Comparator.comparingLong(value -> value.start));
            long rawTotal = ordered.stream().mapToLong(MutableMinute::rawSteps).sum();
            long[][] reconciled = reconcile(ordered, rawTotal, aggregateSteps);
            List<Minute> result = new ArrayList<>();
            for (int i = 0; i < ordered.size(); i++) {
                MutableMinute value = ordered.get(i);
                long[] c = reconciled[i];
                result.add(new Minute(value.start, value.start + MINUTE_MILLIS,
                    sum(c), value.fitSteps, value.fitDistance,
                    c[0], c[1], c[2], c[3], c[4], c[5]));
            }
            return List.copyOf(result);
        }

        List<Minute> buildReferenceOnly() {
            List<MutableMinute> ordered = new ArrayList<>(minutes.values());
            ordered.sort(Comparator.comparingLong(value -> value.start));
            List<Minute> result = new ArrayList<>();
            for (MutableMinute value : ordered) {
                result.add(new Minute(value.start, value.start + MINUTE_MILLIS,
                    0, value.fitSteps, value.fitDistance, 0, 0, 0, 0, 0, 0));
            }
            return List.copyOf(result);
        }

        private MutableMinute minute(long start) {
            return minutes.computeIfAbsent(start, MutableMinute::new);
        }
    }

    private record Slice(long minuteStart, long start, long end) {}

    private PassiveMinuteTimeline() {}

    private static List<Slice> slices(long start, long end) {
        List<Slice> result = new ArrayList<>();
        long cursor = start;
        while (cursor < end) {
            long minute = Math.floorDiv(cursor, MINUTE_MILLIS) * MINUTE_MILLIS;
            long sliceEnd = Math.min(end, minute + MINUTE_MILLIS);
            result.add(new Slice(minute, cursor, sliceEnd));
            cursor = sliceEnd;
        }
        return result;
    }

    private static long[] allocateExactly(long total, List<Slice> slices, long duration) {
        long[] result = new long[slices.size()];
        double[] remainder = new double[slices.size()];
        long assigned = 0;
        for (int i = 0; i < slices.size(); i++) {
            Slice slice = slices.get(i);
            double exact = total * ((slice.end - slice.start) / (double) duration);
            result[i] = (long) Math.floor(exact);
            remainder[i] = exact - result[i];
            assigned += result[i];
        }
        while (assigned < total) {
            int best = 0;
            for (int i = 1; i < remainder.length; i++) {
                if (remainder[i] > remainder[best]) best = i;
            }
            result[best]++;
            remainder[best] = -1;
            assigned++;
        }
        return result;
    }

    private static long[][] reconcile(List<MutableMinute> minutes, long rawTotal,
                                      long aggregateTotal) {
        long[][] result = new long[minutes.size()][6];
        if (rawTotal <= 0 || aggregateTotal <= 0) return result;
        List<Cell> cells = new ArrayList<>();
        long assigned = 0;
        for (int m = 0; m < minutes.size(); m++) {
            for (int c = 0; c < 6; c++) {
                double exact = minutes.get(m).classified[c]
                    * aggregateTotal / (double) rawTotal;
                long floor = (long) Math.floor(exact);
                result[m][c] = floor;
                assigned += floor;
                cells.add(new Cell(m, c, exact - floor));
            }
        }
        cells.sort(Comparator.comparingDouble(Cell::remainder).reversed()
            .thenComparingInt(Cell::minute).thenComparingInt(Cell::classification));
        for (int i = 0; assigned < aggregateTotal && i < cells.size(); i++, assigned++) {
            Cell cell = cells.get(i);
            result[cell.minute][cell.classification]++;
        }
        return result;
    }

    private record Cell(int minute, int classification, double remainder) {}
    private static long sum(long[] values) {
        long result = 0;
        for (long value : values) result += value;
        return result;
    }
}
