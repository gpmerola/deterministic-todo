// Synthetic-only notification harness. No calendar, Todo or network access.
import 'package:deterministic_todo/services/agenda_reminders.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var result = 'FAIL';
  try {
    final now = DateTime.now();
    final event = {
      'id': 'synthetic-${now.microsecondsSinceEpoch}',
      'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'end': now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
    };
    Future<int?> send(List<Object> rows) => AgendaReminders.channel
        .invokeMethod<int>('notifyUrgentVisits', {'events': rows});
    if (await send([event, event]) != 1) throw StateError('delivery');
    if (await send([event]) != 0) throw StateError('duplicate');
    if (await send([]) != 0) throw StateError('empty');
    if (await send([event]) != 0) throw StateError('ledger retention');
    if (await send([
          {'id': 'expired', 'start': 1, 'end': 2},
        ]) !=
        0) {
      throw StateError('expired');
    }
    result = 'PASS';
  } catch (_) {
    // No exception details: fixed test result only.
  }
  debugPrint('AGENDA_URGENT_SMOKE: $result');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(result))),
    ),
  );
}
