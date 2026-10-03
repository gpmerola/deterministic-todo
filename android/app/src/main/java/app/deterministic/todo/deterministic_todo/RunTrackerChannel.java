package app.deterministic.todo.deterministic_todo;

import android.app.Activity;

import app.deterministic.todo.runtracker.DailyStepGoalPolicy;
import app.deterministic.todo.runtracker.LocalStepRecording;
import app.deterministic.todo.runtracker.MovementArchiveCleanup;
import app.deterministic.todo.runtracker.PhoneDailyMovementGateway;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Daily phone steps only; the rest of Movimento is archived. */
public final class RunTrackerChannel {
    private RunTrackerChannel() {}

    public static void register(Activity activity, FlutterEngine engine) {
        MovementArchiveCleanup.runOnce(activity.getApplicationContext());
        LocalStepRecording.schedule(activity.getApplicationContext());
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/run_tracker")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "dailyMovement" -> PhoneDailyMovementGateway.refreshToday(activity,
                        new PhoneDailyMovementGateway.Callback() {
                            @Override public void onSuccess(PhoneDailyMovementGateway.DailySteps steps) {
                                java.util.Map<String, Object> value = new java.util.HashMap<>();
                                value.put("day", steps.day());
                                value.put("steps", steps.steps());
                                value.putAll(LocalStepRecording.statusValues(activity));
                                result.success(value);
                            }
                            @Override public void onError() {
                                result.error("storage_error", "Step storage read failed", null);
                            }
                        });
                    case "requestStepPermission" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 29)
                            androidx.core.app.ActivityCompat.requestPermissions(activity,
                                new String[]{android.Manifest.permission.ACTIVITY_RECOGNITION}, 8040);
                        LocalStepRecording.refreshIfDue(activity);
                        result.success(null);
                    }
                    case "getStepGoal" -> result.success(activity.getSharedPreferences(
                        "movement_profile", Activity.MODE_PRIVATE).getInt(
                        "daily_step_goal", DailyStepGoalPolicy.DEFAULT_GOAL));
                    case "setStepGoal" -> {
                        Number requested = call.argument("goal");
                        if (requested == null) {
                            result.error("invalid_goal", "Missing daily step goal", null);
                            return;
                        }
                        int goal = DailyStepGoalPolicy.normalize(requested.intValue());
                        activity.getSharedPreferences("movement_profile", Activity.MODE_PRIVATE)
                            .edit().putInt("daily_step_goal", goal).apply();
                        result.success(goal);
                    }
                    default -> result.notImplemented();
                }
            });
    }
}
