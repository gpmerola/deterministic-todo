package app.deterministic.todo.runtracker;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.Map;

/** Personal parameters stay in the isolated local movement store. */
public record MovementProfile(double weightKg, double walkingStride, double runningStride) {
    public MovementProfile {
        if (!valid(weightKg, 25, 300) || !valid(walkingStride, .30, 1.50)
            || !valid(runningStride, .40, 2.50)) throw new IllegalArgumentException("invalid_profile");
    }

    private static boolean valid(double value, double min, double max) {
        return Double.isFinite(value) && value >= min && value <= max;
    }

    public static MovementProfile read(Context context) {
        SharedPreferences p = context.getSharedPreferences("movement_profile", Context.MODE_PRIVATE);
        return new MovementProfile(p.getFloat("weight_kg", 70),
            p.getFloat("walking_stride_meters", .72f), p.getFloat("running_stride_meters", 1.05f));
    }

    public void save(Context context) {
        context.getSharedPreferences("movement_profile", Context.MODE_PRIVATE).edit()
            .putFloat("weight_kg", (float) weightKg)
            .putFloat("walking_stride_meters", (float) walkingStride)
            .putFloat("running_stride_meters", (float) runningStride).apply();
    }

    public Map<String, Object> values() {
        return Map.of("weight_kg", weightKg, "walking_stride_meters", walkingStride,
            "running_stride_meters", runningStride);
    }
}
