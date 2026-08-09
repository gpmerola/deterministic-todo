package app.deterministic.todo.runtracker;

/** Stateful, deterministic filter. It never fabricates or smooths coordinates. */
public final class GpsTrackFilter {
    public static final float MAX_ACCURACY_METERS = 35f;
    public static final double MAX_RUNNING_SPEED_MPS = 12.0;
    // This is a GPS-segment plausibility ceiling, not a classification threshold.
    // Headroom avoids discarding ordinary fixes affected by several metres of uncertainty.
    public static final double MAX_WALKING_SPEED_MPS = 6.0;

    public record Sample(long timeMillis, double latitude, double longitude, float accuracyMeters) {}
    public record Decision(boolean accepted, String reason, double segmentMeters, double totalMeters) {}

    private Sample previous;
    private Sample last;
    private Sample discontinuityCandidate;
    private double totalMeters;
    private final double maximumSpeedMps;

    public GpsTrackFilter() { this(MAX_RUNNING_SPEED_MPS); }

    public GpsTrackFilter(double maximumSpeedMps) {
        if (!Double.isFinite(maximumSpeedMps) || maximumSpeedMps <= 0) {
            throw new IllegalArgumentException("maximumSpeedMps must be positive");
        }
        this.maximumSpeedMps = maximumSpeedMps;
    }

    public Decision evaluate(Sample sample) {
        return evaluate(sample, false);
    }

    /**
     * Evaluates a fix, optionally using a hardware step increment as evidence that the
     * phone is moving. Step evidence only lowers the stationary-noise gate; all accuracy,
     * speed, discontinuity and zigzag protections remain active.
     */
    public Decision evaluate(Sample sample, boolean stepMovementObserved) {
        return evaluate(sample, stepMovementObserved, false);
    }

    public Decision evaluate(
        Sample sample, boolean stepMovementObserved, boolean requireStepMovement
    ) {
        String invalid = invalidReason(sample);
        if (invalid != null) return reject(invalid);
        if (last == null) {
            last = sample;
            return new Decision(true, null, 0, totalMeters);
        }
        long elapsedMillis = sample.timeMillis - last.timeMillis;
        if (elapsedMillis <= 0) return reject("timestamp_non_monotonic");

        if (requireStepMovement && !stepMovementObserved) {
            discontinuityCandidate = null;
            return reject("stationary_step_gate");
        }

        if (discontinuityCandidate != null) {
            long candidateElapsed = sample.timeMillis - discontinuityCandidate.timeMillis;
            if (candidateElapsed > 0) {
                double candidateSegment = distanceMeters(discontinuityCandidate, sample);
                double candidateSpeed = candidateSegment / (candidateElapsed / 1000.0);
                if (candidateSpeed <= maximumSpeedMps) {
                    double recoveredSegment = distanceMeters(last, sample);
                    double recoveredSpeed = recoveredSegment / (elapsedMillis / 1000.0);
                    if (recoveredSpeed <= maximumSpeedMps) {
                        // The first fix looked too fast only because it arrived early.
                        // Once the confirming fix makes the complete interval plausible,
                        // retain the chord instead of losing genuine movement.
                        previous = last;
                        last = sample;
                        discontinuityCandidate = null;
                        totalMeters += recoveredSegment;
                        return new Decision(true, null, recoveredSegment, totalMeters);
                    }
                    // Two coherent fixes on the new track confirm a GPS discontinuity.
                    // Re-anchor without ever adding the jump to the distance.
                    last = sample;
                    previous = null;
                    discontinuityCandidate = null;
                    return reject("gps_discontinuity_reanchor");
                }
            }
            discontinuityCandidate = null;
        }

        double segment = distanceMeters(last, sample);
        double noiseRadius = Math.max(2.5, Math.min(last.accuracyMeters, sample.accuracyMeters) * 0.35);
        if (stepMovementObserved) noiseRadius = Math.max(1.0, noiseRadius * 0.45);
        if (segment <= noiseRadius) return reject("stationary_accuracy_noise");

        double speed = segment / (elapsedMillis / 1000.0);
        if (speed > maximumSpeedMps) {
            discontinuityCandidate = sample;
            return reject("implausible_speed_jump");
        }

        if (previous != null && segment < 30 && distanceMeters(previous, last) < 30) {
            double turn = turnDegrees(previous, last, sample);
            double direct = distanceMeters(previous, sample);
            double detour = distanceMeters(previous, last) + segment;
            if (turn > 145 && direct < detour * 0.45) return reject("gps_zigzag");
        }

        previous = last;
        last = sample;
        totalMeters += segment;
        return new Decision(true, null, segment, totalMeters);
    }

    public double totalMeters() { return totalMeters; }

    private static String invalidReason(Sample sample) {
        if (!Double.isFinite(sample.latitude) || !Double.isFinite(sample.longitude)
            || Math.abs(sample.latitude) > 90 || Math.abs(sample.longitude) > 180) {
            return "invalid_coordinate";
        }
        if (!Float.isFinite(sample.accuracyMeters) || sample.accuracyMeters <= 0
            || sample.accuracyMeters > MAX_ACCURACY_METERS) {
            return "poor_accuracy";
        }
        return null;
    }

    private Decision reject(String reason) {
        return new Decision(false, reason, 0, totalMeters);
    }

    public static double distanceMeters(Sample a, Sample b) {
        double lat1 = Math.toRadians(a.latitude);
        double lat2 = Math.toRadians(b.latitude);
        double dLat = lat2 - lat1;
        double dLon = Math.toRadians(b.longitude - a.longitude);
        double h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 6_371_000.0 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
    }

    private static double turnDegrees(Sample a, Sample b, Sample c) {
        double first = bearing(a, b);
        double second = bearing(b, c);
        double delta = Math.abs(first - second) % 360;
        return delta > 180 ? 360 - delta : delta;
    }

    private static double bearing(Sample a, Sample b) {
        double lat1 = Math.toRadians(a.latitude);
        double lat2 = Math.toRadians(b.latitude);
        double lon = Math.toRadians(b.longitude - a.longitude);
        return (Math.toDegrees(Math.atan2(
            Math.sin(lon) * Math.cos(lat2),
            Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lon)
        )) + 360) % 360;
    }
}
