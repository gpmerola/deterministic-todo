package app.deterministic.todo.deterministic_todo;

import android.app.Activity;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import app.deterministic.todo.h96remote.H96RemoteController;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Thin bridge to the isolated H96 Remote module (docs/architecture/H96_REMOTE.md).
 * The controller is created on first use, so the feature costs nothing at app start.
 * To remove the feature delete this file, its register line in each MainActivity and the module.
 */
public final class H96RemoteChannel {
    private H96RemoteChannel() {}

    public static void register(Activity activity, FlutterEngine engine) {
        MethodChannel channel = new MethodChannel(
            engine.getDartExecutor().getBinaryMessenger(), "app.deterministic.todo/h96_remote");
        H96RemoteController[] controller = new H96RemoteController[1];
        channel.setMethodCallHandler((call, result) -> {
            if (controller[0] == null) {
                controller[0] = new H96RemoteController(activity, new H96RemoteController.Events() {
                    @Override public void onState(String state, String failure) {
                        Map<String, Object> value = new HashMap<>();
                        value.put("state", state);
                        value.put("failure", failure);
                        channel.invokeMethod("state", value);
                    }

                    @Override public void onVolume(int level, int max, boolean muted) {
                        Map<String, Object> value = new HashMap<>();
                        value.put("level", level);
                        value.put("max", max);
                        value.put("muted", muted);
                        channel.invokeMethod("volume", value);
                    }

                    @Override public void onLatency(long millis) {
                        Map<String, Object> value = new HashMap<>();
                        value.put("millis", millis);
                        channel.invokeMethod("latency", value);
                    }
                });
            }
            H96RemoteController remote = controller[0];
            switch (call.method) {
                case "status" -> result.success(remote.status());
                case "discover" -> remote.discover(new H96RemoteController.Result<List<Map<String, Object>>>() {
                    @Override public void ok(List<Map<String, Object>> value) { result.success(value); }
                    @Override public void error(String code) { result.error(code, code, null); }
                });
                case "startPairing" -> remote.startPairing(call.argument("host"), call.argument("name"), voidResult(result));
                case "finishPairing" -> remote.finishPairing(call.argument("code"), voidResult(result));
                case "cancelPairing" -> { remote.cancelPairing(); result.success(null); }
                case "connect" -> { remote.connect(); result.success(null); }
                case "disconnect" -> { remote.disconnect(); result.success(null); }
                case "send" -> result.success(remote.send(call.argument("command")));
                case "hold" -> result.success(remote.hold(call.argument("command"),
                    Boolean.TRUE.equals(call.argument("start"))));
                case "sendText" -> result.success(remote.sendText(call.argument("text")));
                case "forget" -> { remote.forget(); result.success(null); }
                default -> result.notImplemented();
            }
        });
    }

    private static H96RemoteController.Result<Void> voidResult(MethodChannel.Result result) {
        return new H96RemoteController.Result<Void>() {
            @Override public void ok(Void value) { result.success(null); }
            @Override public void error(String code) { result.error(code, code, null); }
        };
    }
}
