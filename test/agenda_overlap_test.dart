import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/ui/views/agenda_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

AgendaEntry _event(
  String id,
  int startHour,
  int startMinute,
  int endHour,
  int endMinute, {
  bool allDay = false,
  String? taskId,
}) => AgendaEntry(
  instanceId: id,
  calendarIds: const ['c'],
  title: id,
  start: DateTime(2026, 10, 5, startHour, startMinute),
  end: DateTime(2026, 10, 5, endHour, endMinute),
  allDay: allDay,
  taskId: taskId,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('overlapping timed events clash both ways, in start order', () {
    final clashes = agendaOverlaps([
      _event('a', 9, 0, 10, 0),
      _event('b', 9, 30, 11, 0),
      _event('c', 10, 30, 10, 45),
      _event('d', 11, 0, 12, 0),
    ]);
    expect(clashes['a']!.map((e) => e.instanceId), ['b']);
    expect(clashes['b']!.map((e) => e.instanceId), ['a', 'c']);
    expect(clashes['c']!.map((e) => e.instanceId), ['b']);
    // Back-to-back is not a clash.
    expect(clashes.containsKey('d'), isFalse);
  });

  test('all-day events, tasks and empty events never clash', () {
    final clashes = agendaOverlaps([
      _event('meeting', 9, 0, 10, 0),
      _event('holiday', 0, 0, 0, 0, allDay: true).copyEnd(),
      _event('task', 0, 0, 0, 0, taskId: 't').copyEnd(),
      _event('zero', 9, 30, 9, 30),
    ]);
    expect(clashes, isEmpty);
  });

  test('order of input does not change the result', () {
    final events = [
      _event('x', 14, 0, 15, 0),
      _event('y', 14, 0, 15, 0),
      _event('z', 14, 59, 16, 0),
    ];
    Map<String, List<String>> ids(Map<String, List<AgendaEntry>> value) => {
      for (final entry in value.entries)
        entry.key: [for (final e in entry.value) e.instanceId],
    };
    expect(ids(agendaOverlaps(events.reversed)), ids(agendaOverlaps(events)));
  });

  testWidgets('event sheet lists the clashing events', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaEventSheet(
            entry: _event('Ward round', 9, 0, 10, 0),
            calendarName: 'KCL',
            editable: false,
            zoneLabel: 'Europe/London · UTC+1',
            overlaps: [_event('Supervisione', 9, 30, 10, 30)],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('agenda-sheet-overlaps')), findsOneWidget);
    expect(find.textContaining('09:30–10:30 Supervisione'), findsOneWidget);
  });
}

extension on AgendaEntry {
  /// Gives the all-day/task fixtures a real one-day span.
  AgendaEntry copyEnd() => AgendaEntry(
    instanceId: instanceId,
    calendarIds: calendarIds,
    title: title,
    start: DateTime(2026, 10, 5),
    end: DateTime(2026, 10, 6),
    allDay: allDay,
    taskId: taskId,
  );
}
