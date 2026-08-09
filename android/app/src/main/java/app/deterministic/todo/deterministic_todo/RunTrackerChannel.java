package app.deterministic.todo.deterministic_todo;

import android.app.Activity;
import android.content.Intent;

import app.deterministic.todo.runtracker.RunTrackerActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class RunTrackerChannel {
    private RunTrackerChannel() {}

    public static void register(Activity activity, FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/run_tracker")
            .setMethodCallHandler((call, result) -> {
                if (!"open".equals(call.method)) { result.notImplemented(); return; }
                activity.startActivity(new Intent(activity, RunTrackerActivity.class));
                result.success(null);
            });
    }
}
