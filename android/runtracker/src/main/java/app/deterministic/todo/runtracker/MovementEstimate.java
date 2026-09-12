package app.deterministic.todo.runtracker;

public record MovementEstimate(long steps, double distanceMeters, double activeCalories) {
    public static final double DEFAULT_STRIDE_METERS = 0.72;
    public static final double DEFAULT_WEIGHT_KG = 70.0;
    public static final double WALKING_KCAL_PER_KG_KM = 0.50;

    public static MovementEstimate fromSteps(long steps, double strideMeters, double weightKg) {
        long safeSteps = Math.max(0, steps);
        double safeStride = bounded(strideMeters, 0.30, 1.50, DEFAULT_STRIDE_METERS);
        double safeWeight = bounded(weightKg, 25.0, 300.0, DEFAULT_WEIGHT_KG);
        double meters = safeSteps * safeStride;
        double calories = safeWeight * (meters / 1000.0) * WALKING_KCAL_PER_KG_KM;
        return new MovementEstimate(safeSteps, meters, calories);
    }

    private static double bounded(double value, double min, double max, double fallback) {
        return Double.isFinite(value) && value >= min && value <= max ? value : fallback;
    }
}
