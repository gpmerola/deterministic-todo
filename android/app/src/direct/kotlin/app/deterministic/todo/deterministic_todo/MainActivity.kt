package app.deterministic.todo.deterministic_todo

import io.flutter.embedding.engine.FlutterEngine

class MainActivity : CalendarShortcutActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RunTrackerChannel.register(this, flutterEngine)
        RuntimeMetricsChannel.register(flutterEngine)
        AgendaChannel.register(this, flutterEngine)
    }
}
