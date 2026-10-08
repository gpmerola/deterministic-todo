import 'package:flutter/services.dart';

/// Foreground Android shortcut bridge, independent of background calendar sync.
class CalendarShortcutService {
  static const channel = MethodChannel(
    'app.deterministic.todo/calendar_shortcut',
  );
  bool _attached = false;
  Future<void> _work = Future.value();

  Future<void> attach(Future<void> Function() openCalendar) async {
    _attached = true;
    Future<void> consume() {
      return _work = _work
          .then((_) async {
            if (!_attached) return;
            final pending =
                await channel.invokeMethod<bool>('consumeLaunch') ?? false;
            if (_attached && pending) await openCalendar();
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
