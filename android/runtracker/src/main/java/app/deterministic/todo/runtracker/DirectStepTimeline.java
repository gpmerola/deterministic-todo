package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.List;

/** Compact, bounded diagnostic timeline for the session hardware step counter. */
final class DirectStepTimeline {
    record Sample(long timeMillis, long steps, String status) {}

    private static final int MAX_SAMPLES = 10_000;
    private final ArrayList<Sample> samples = new ArrayList<>();

    synchronized void add(long timeMillis, long steps, String status) {
        if (timeMillis <= 0 || steps < 0 || status == null || status.isBlank()) return;
        Sample next = new Sample(timeMillis, steps, clean(status));
        if (!samples.isEmpty()) {
            Sample last = samples.get(samples.size() - 1);
            if (last.steps == next.steps && last.status.equals(next.status)) return;
        }
        if (samples.size() == MAX_SAMPLES) samples.remove(0);
        samples.add(next);
    }

    synchronized List<Sample> snapshot() { return List.copyOf(samples); }

    synchronized String encode() {
        StringBuilder out = new StringBuilder(samples.size() * 28);
        for (Sample sample : samples) {
            out.append(sample.timeMillis).append(',').append(sample.steps).append(',')
                .append(sample.status).append('\n');
        }
        return out.toString();
    }

    static DirectStepTimeline decode(String encoded) {
        DirectStepTimeline timeline = new DirectStepTimeline();
        if (encoded == null || encoded.isBlank()) return timeline;
        for (String line : encoded.split("\\n")) {
            String[] fields = line.split(",", 3);
            if (fields.length != 3) continue;
            try { timeline.add(Long.parseLong(fields[0]), Long.parseLong(fields[1]), fields[2]); }
            catch (NumberFormatException ignored) {}
        }
        return timeline;
    }

    private static String clean(String value) {
        return value.replace(',', '_').replace('\n', '_').replace('\r', '_');
    }
}
