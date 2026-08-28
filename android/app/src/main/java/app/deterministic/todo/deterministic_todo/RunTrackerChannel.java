package app.deterministic.todo.deterministic_todo;

import android.app.Activity;
import android.content.Intent;

import app.deterministic.todo.runtracker.RunTrackerActivity;
import app.deterministic.todo.runtracker.DiagnosticDriveScheduler;
import app.deterministic.todo.runtracker.ActivityClassifier;
import app.deterministic.todo.runtracker.PassiveMovementAuditScheduler;
import app.deterministic.todo.runtracker.IntensiveDiagnosticScheduler;
import app.deterministic.todo.runtracker.DailyMovement;
import app.deterministic.todo.runtracker.DailyStepGoalPolicy;
import app.deterministic.todo.runtracker.PhoneDailyMovementGateway;
import app.deterministic.todo.runtracker.BipUAutomaticSyncScheduler;
import app.deterministic.todo.runtracker.MovementDashboardBridge;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RunTrackerChannel {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private RunTrackerChannel() {}

    public static void register(Activity activity, FlutterEngine engine) {
        DiagnosticDriveScheduler.schedule(activity.getApplicationContext());
        ActivityClassifier.register(activity.getApplicationContext());
        PassiveMovementAuditScheduler.refreshIfEnabled(activity.getApplicationContext());
        IntensiveDiagnosticScheduler.refreshIfEnabled(activity.getApplicationContext());
        BipUAutomaticSyncScheduler.schedule(activity.getApplicationContext());
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/run_tracker")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "open" -> {
                        activity.startActivity(new Intent(activity, RunTrackerActivity.class));
                        result.success(null);
                    }
                    case "dailyMovement" -> {
                        BipUAutomaticSyncScheduler.refreshIfDue(activity.getApplicationContext());
                        PhoneDailyMovementGateway.refreshToday(activity,
                        new PhoneDailyMovementGateway.Callback() {
                            @Override public void onSuccess(DailyMovement movement, long phoneSteps,
                                                            long bipSteps, String fusionSource) {
                                java.util.Map<String, Object> value = new java.util.HashMap<>();
                                value.put("day", movement.day);
                                value.put("steps", movement.steps);
                                value.put("distance_m", movement.estimatedDistanceMeters);
                                value.put("calories", movement.estimatedActiveCalories);
                                value.put("updated_at_ms", movement.updatedAtMillis);
                                value.put("phone_steps", phoneSteps);
                                value.put("bip_steps", bipSteps);
                                value.put("source", fusionSource);
                                result.success(value);
                            }
                            @Override public void onPermissionRequired() {
                                result.error("permission_required", "Activity recognition permission required", null);
                            }
                            @Override public void onUnavailable() {
                                result.error("unavailable", "Step counter unavailable", null);
                            }
                            @Override public void onError() {
                                result.error("sensor_error", "Step counter read failed", null);
                            }
                        });
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
                    case "movementState" -> IO.execute(() -> {
                        java.util.Map<String, Object> value =
                            MovementDashboardBridge.snapshot(activity.getApplicationContext());
                        activity.runOnUiThread(() -> result.success(value));
                    });
                    case "startMovement" -> {
                        String type = call.argument("activity_type");
                        result.success(MovementDashboardBridge.start(activity, type));
                    }
                    case "stopMovement" -> {
                        MovementDashboardBridge.stop(activity.getApplicationContext());
                        result.success(null);
                    }
                    case "uploadMovementData" -> IO.execute(() -> {
                        String value = MovementDashboardBridge.uploadAll(
                            activity.getApplicationContext());
                        activity.runOnUiThread(() -> result.success(value));
                    });
                    case "setPassiveMonitoring" -> {
                        Boolean enabled = call.argument("enabled");
                        if (enabled == null) {
                            result.error("invalid_state", "Missing enabled state", null);
                            return;
                        }
                        result.success(MovementDashboardBridge.setPassiveMonitoring(
                            activity.getApplicationContext(), enabled));
                    }
                    default -> result.notImplemented();
                }
            });
    }
}
