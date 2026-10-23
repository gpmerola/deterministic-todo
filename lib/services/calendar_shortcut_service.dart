import 'package:flutter/services.dart';

/// Where a Semble conflict notification asks the Calendar to land (build
/// 306): the event starting at [start] when [single], otherwise its day.
final class CalendarLaunch {
  const CalendarLaunch(this.start, {required this.single});
  final DateTime start;
  final bool single;

  /// The platform answer: false, true (just the Calendar) or {start, single}.
  static CalendarLaunch? parse(Object? value) {
    if (value is! Map) return null;
    final start = value['start'];
    if (start is! int || start <= 0) return null;
    return CalendarLaunch(
      DateTime.fromMillisecondsSinceEpoch(start),
      single: value['single'] == true,
    );
  }
}

/// Foreground Android shortcut bridge, independent of background calendar sync.
class CalendarShortcutService {
  static const channel = MethodChannel(
    'app.deterministic.todo/calendar_shortcut',
  );
  bool _attached = false;
  Future<void> _work = Future.value();

  Future<void> attach(
    Future<void> Function(CalendarLaunch? target) openCalendar,
  ) async {
    _attached = true;
    Future<void> consume() {
      return _work = _work
          .then((_) async {
            if (!_attached) return;
            final pending = await channel.invokeMethod<Object>('consumeLaunch');
            if (!_attached || pending == null || pending == false) return;
            await openCalendar(CalendarLaunch.parse(pending));
          })
          .catchError((Object _) {
            // Platform errors contain no user data and do not block normal startup.
          });
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'calendarRequested') await consume();
    });
    await consume();
  }

  void detach() {
    _attached = false;
    channel.setMethodCallHandler(null);
  }

  Future<String> pin() async =>
      await channel.invokeMethod<String>('pin') ?? 'unsupported';
}
