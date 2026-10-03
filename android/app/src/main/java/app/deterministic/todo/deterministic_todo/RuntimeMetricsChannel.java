package app.deterministic.todo.deterministic_todo;

import android.os.Debug;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class RuntimeMetricsChannel {
    private RuntimeMetricsChannel() {}

    public static void register(FlutterEngine engine) {
        new MethodChannel(
            engine.getDartExecutor().getBinaryMessenger(),
            "app.deterministic.todo/runtime_metrics"
        ).setMethodCallHandler((call, result) -> {
            if (!"memorySnapshot".equals(call.method)) {
                result.notImplemented();
                return;
            }
            Debug.MemoryInfo info = new Debug.MemoryInfo();
            Debug.getMemoryInfo(info);
            Map<String, String> stats = info.getMemoryStats();
            Map<String, Integer> values = new HashMap<>();
            values.put("total_pss_kb", info.getTotalPss());
            values.put("java_heap_kb", parseKilobytes(stats.get("summary.java-heap")));
            values.put("native_heap_kb", parseKilobytes(stats.get("summary.native-heap")));
            values.put("graphics_kb", parseKilobytes(stats.get("summary.graphics")));
            result.success(values);
        });
    }

    private static int parseKilobytes(String value) {
        if (value == null) return 0;
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }
}
