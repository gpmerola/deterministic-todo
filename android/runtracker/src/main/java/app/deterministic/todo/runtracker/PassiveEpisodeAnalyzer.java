package app.deterministic.todo.runtracker;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Diagnostic-only segmentation. It never changes the movement estimate. */
final class PassiveEpisodeAnalyzer {
    static final long MINUTE_MS = 60_000L;
    static final int ACTIVE_STEP_THRESHOLD = 20;
    static final int MAX_BRIDGED_PAUSE_MINUTES = 1;

    record MinuteEvidence(long startMillis, long endMillis, long todoSteps,
                          double todoDistanceMeters, long walkingSteps,
                          long runningSteps, long unknownSteps, long stillSteps,
                          long vehicleSteps, long bicycleSteps, long fitSteps,
                          Double fitDistanceMeters, long bipSteps,
                          Integer bipHeartRate, int bipSamples) {
        boolean active() { return todoSteps >= ACTIVE_STEP_THRESHOLD || bipSteps >= ACTIVE_STEP_THRESHOLD; }
    }

    record Episode(long startMillis, long endMillis, String activity,
                   int activeMinutes, int pauseMinutes, long todoSteps,
                   double todoDistanceMeters, long fitSteps,
                   Double fitDistanceMeters, long bipSteps,
                   Integer bipHeartRateMean, long walkingSteps,
                   long runningSteps, long unknownSteps, long stillSteps,
                   long vehicleSteps, long bicycleSteps, List<String> qualityFlags) {
        Double distancePercentVsFit() {
            return fitDistanceMeters == null || fitDistanceMeters == 0 ? null
                : (todoDistanceMeters - fitDistanceMeters) * 100.0 / fitDistanceMeters;
        }
    }

    private PassiveEpisodeAnalyzer() {}

    static List<Episode> episodes(List<MinuteEvidence> source) {
        List<MinuteEvidence> rows = new ArrayList<>(source);
        rows.sort(Comparator.comparingLong(MinuteEvidence::startMillis));
        List<Episode> result = new ArrayList<>();
        List<MinuteEvidence> current = new ArrayList<>();
        int pendingPauses = 0;
        long previousStart = Long.MIN_VALUE;
        for (MinuteEvidence row : rows) {
            if (!current.isEmpty() && previousStart != Long.MIN_VALUE) {
                long missingMinutes = Math.max(0,
                    (row.startMillis - previousStart) / MINUTE_MS - 1);
                if (missingMinutes > MAX_BRIDGED_PAUSE_MINUTES) {
                    finish(result, current, pendingPauses);
                    current.clear();
                    pendingPauses = 0;
                } else {
                    for (int i = 1; i <= missingMinutes; i++) {
                        long start = previousStart + i * MINUTE_MS;
                        current.add(new MinuteEvidence(start, start + MINUTE_MS,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, null, 0, null, 0));
                        pendingPauses++;
                    }
                }
            }
            if (row.active()) {
                current.add(row);
                pendingPauses = 0;
            } else if (!current.isEmpty()) {
                pendingPauses++;
                if (pendingPauses <= MAX_BRIDGED_PAUSE_MINUTES) current.add(row);
                else {
                    for (int i = 0; i < pendingPauses; i++)
                        if (!current.isEmpty() && !current.get(current.size() - 1).active())
                            current.remove(current.size() - 1);
                    finish(result, current, 0);
                    current.clear();
                    pendingPauses = 0;
                }
            }
            previousStart = row.startMillis;
        }
        while (!current.isEmpty() && !current.get(current.size() - 1).active())
            current.remove(current.size() - 1);
        finish(result, current, 0);
        return result;
    }

    private static void finish(List<Episode> result, List<MinuteEvidence> rows,
                               int ignoredTrailingPauses) {
        if (rows.isEmpty()) return;
        long todoSteps = 0, fitSteps = 0, bipSteps = 0, walking = 0, running = 0;
        long unknown = 0, still = 0, vehicle = 0, bicycle = 0;
        double todoDistance = 0, fitDistance = 0;
        boolean hasFitDistance = false;
        long heartRateSum = 0;
        int heartRateSamples = 0, activeMinutes = 0, pauseMinutes = 0;
        for (MinuteEvidence row : rows) {
            if (row.active()) activeMinutes++; else pauseMinutes++;
            todoSteps += row.todoSteps;
            todoDistance += row.todoDistanceMeters;
            fitSteps += row.fitSteps;
            if (row.fitDistanceMeters != null) {
                fitDistance += row.fitDistanceMeters;
                hasFitDistance = true;
            }
            bipSteps += row.bipSteps;
            walking += row.walkingSteps;
            running += row.runningSteps;
            unknown += row.unknownSteps;
            still += row.stillSteps;
            vehicle += row.vehicleSteps;
            bicycle += row.bicycleSteps;
            if (row.bipHeartRate != null && row.bipHeartRate > 0) {
                heartRateSum += row.bipHeartRate;
                heartRateSamples++;
            }
        }
        String activity = running > walking && running > unknown ? "running"
            : walking >= running && walking >= unknown ? "walking" : "mixed_or_unknown";
        List<String> flags = new ArrayList<>();
        if (unknown + still > todoSteps * 0.2) flags.add("material_uncertain_steps");
        if (vehicle + bicycle > 0) flags.add("transport_overlap");
        if (!hasFitDistance) flags.add("fit_distance_missing");
        if (bipSteps == 0) flags.add("bip_not_observed");
        result.add(new Episode(rows.get(0).startMillis,
            rows.get(rows.size() - 1).endMillis, activity, activeMinutes,
            pauseMinutes, todoSteps, todoDistance, fitSteps,
            hasFitDistance ? fitDistance : null, bipSteps,
            heartRateSamples == 0 ? null : (int) Math.round(heartRateSum / (double) heartRateSamples),
            walking, running, unknown, still, vehicle, bicycle, List.copyOf(flags)));
    }
}
