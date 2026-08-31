package app.deterministic.todo.runtracker;

public record MixedMovementEstimate(long walkingSteps, long runningSteps,
    long unknownSteps, long excludedSteps, double distanceMeters, double activeCalories) {
    public static final double DEFAULT_RUNNING_STRIDE_METERS = 1.05;
    public static final double RUNNING_KCAL_PER_KG_KM = 1.0;

    public static MixedMovementEstimate calculate(long walking, long running, long unknown,
                                            long excluded, double walkingStride,
                                            double runningStride, double weightKg) {
        double walkingMeters = Math.max(0, walking) * walkingStride;
        double runningMeters = Math.max(0, running) * runningStride;
        double unknownMeters = Math.max(0, unknown) * walkingStride;
        double calories = weightKg * ((walkingMeters + unknownMeters) / 1000.0)
            * MovementEstimate.WALKING_KCAL_PER_KG_KM
            + weightKg * (runningMeters / 1000.0) * RUNNING_KCAL_PER_KG_KM;
        return new MixedMovementEstimate(Math.max(0, walking), Math.max(0, running),
            Math.max(0, unknown), Math.max(0, excluded),
            walkingMeters + runningMeters + unknownMeters, calories);
    }
}
