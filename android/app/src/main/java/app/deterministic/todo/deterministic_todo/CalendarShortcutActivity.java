package app.deterministic.todo.deterministic_todo;

import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Shared by all distribution flavours; the shortcut stays inside its package. */
public class CalendarShortcutActivity extends FlutterActivity {
    private static final String ID = "calendar";
    private final CalendarLaunchRequest launch = new CalendarLaunchRequest();
    private MethodChannel channel;

    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
            "app.deterministic.todo/agenda_reminder_permissions").setMethodCallHandler((call, result) -> {
                if (!call.method.equals("request") && !call.method.equals("requestOnce")) {
                    result.notImplemented(); return;
                }
                boolean automatic = call.method.equals("requestOnce");
                android.content.SharedPreferences preferences = AgendaReminders.prefs(this);
                if (automatic && preferences.getBoolean("permission_asked", false)) {
                    result.success(null); return;
                }
                preferences.edit().putBoolean("permission_asked", true).apply();
                if (android.os.Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    if (!automatic && preferences.getBoolean("notification_requested", false)
                        && !shouldShowRequestPermissionRationale(android.Manifest.permission.POST_NOTIFICATIONS)) {
                        startActivity(new Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName()));
                    } else {
                        preferences.edit().putBoolean("notification_requested", true).apply();
                        requestPermissions(new String[] {android.Manifest.permission.POST_NOTIFICATIONS}, 7310);
                    }
                } else if (!automatic) {
                    if (!Boolean.TRUE.equals(AgendaReminders.status(this).get("notifications"))) {
                        startActivity(new Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName())
                            .putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, AgendaReminders.CHANNEL));
                    } else if (!AgendaReminders.exact(this) && android.os.Build.VERSION.SDK_INT >= 31) {
                        startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            android.net.Uri.parse("package:" + getPackageName())));
                    }
                }
                result.success(null);
            });
        if (getIntent() != null) launch.accept(getIntent().getAction(), getPackageName());
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "app.deterministic.todo/calendar_shortcut");
        channel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("consumeLaunch")) {
                boolean requested = launch.consume();
                if (requested && getIntent() != null) getIntent().setAction(Intent.ACTION_MAIN);
                result.success(requested);
            } else if (call.method.equals("pin")) {
                try {
                    result.success(pin());
                } catch (RuntimeException error) {
                    result.error("shortcut_unavailable", "Impossibile aggiungere il collegamento.", null);
                }
            } else result.notImplemented();
        });
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (launch.accept(intent.getAction(), getPackageName()) && channel != null) {
            // Keep it pending until Dart consumes it, including during startup.
            channel.invokeMethod("calendarRequested", null);
        }
    }

    private String pin() {
        ShortcutManager manager = getSystemService(ShortcutManager.class);
        if (manager == null || !manager.isRequestPinShortcutSupported()) return "unsupported";
        for (ShortcutInfo existing : manager.getPinnedShortcuts()) {
            if (existing.getId().equals(ID)) return "alreadyPinned";
        }
        Intent intent = new Intent(this, getClass())
                .setAction(getPackageName() + ".OPEN_CALENDAR")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        ShortcutInfo shortcut = new ShortcutInfo.Builder(this, ID)
                .setShortLabel("Calendario")
                .setLongLabel("Apri Calendario")
                .setIcon(Icon.createWithResource(this, R.drawable.ic_calendar_shortcut))
                .setIntent(intent)
                .build();
        return manager.requestPinShortcut(shortcut, null) ? "requested" : "unsupported";
    }
}
