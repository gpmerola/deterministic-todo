import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/task.dart';

/// Current civil day for date-derived views.
///
/// A screen left open across midnight (typically a Web tab) would otherwise
/// keep showing yesterday's Today until something else rebuilt it. One timer
/// is armed for the next local midnight and re-armed after it fires; nothing
/// polls. Timers can fire late while the process is suspended, so the shell
/// also calls [refresh] when the app returns to the foreground.
class CivilDayClock extends ChangeNotifier {
  CivilDayClock({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _today = CivilDate.fromDateTime(_now());
    _arm();
  }

  final DateTime Function() _now;
  late CivilDate _today;
  Timer? _timer;

  CivilDate get today => _today;

  /// Re-reads the date immediately and re-arms the midnight timer.
  void refresh() {
    final current = CivilDate.fromDateTime(_now());
    if (current != _today) {
      _today = current;
      notifyListeners();
    }
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final now = _now();
    // DateTime normalises day overflow and follows local DST transitions.
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      refresh,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
