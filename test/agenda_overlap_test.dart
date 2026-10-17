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
  timelineScaleTests();
  dragSpanTests();
  mergeStatusTests();
  holidayTests();

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

TimelineBlock _block(int start, int end) => TimelineBlock(
  entry: _event('x', 0, 0, 0, 1),
  startMinute: start,
  endMinute: end,
  column: 0,
  columns: 1,
);

void timelineScaleTests() {
  test('empty night hours fold, useful hours keep full height', () {
    final scale = TimelineScale.forBlocks(const [], hourHeight: 60);
    expect(scale.isFolded(3), isTrue);
    expect(scale.isFolded(7), isFalse);
    expect(scale.isFolded(20), isFalse);
    expect(scale.isFolded(21), isTrue);
    // 7 folded hours, 14 full, 3 folded.
    expect(scale.total, 7 * 14 + 14 * 60 + 3 * 14);
    expect(scale.y(7 * 60), 7 * 14);
    expect(scale.y(7 * 60 + 30), 7 * 14 + 30);
  });

  test('an early or late event unfolds its hours', () {
    final scale = TimelineScale.forBlocks([
      _block(6 * 60 + 30, 7 * 60),
      _block(22 * 60, 23 * 60 + 10),
    ], hourHeight: 60);
    expect(scale.isFolded(6), isFalse);
    expect(scale.isFolded(22), isFalse);
    expect(scale.isFolded(23), isFalse);
    expect(scale.isFolded(5), isTrue);
  });

  test('minuteAt inverts y', () {
    final scale = TimelineScale.forBlocks([
      _block(9 * 60, 10 * 60),
    ], hourHeight: 48);
    for (final minute in [0, 125, 7 * 60, 9 * 60 + 30, 20 * 60 + 59, 23 * 60]) {
      expect(
        scale.minuteAt(scale.y(minute)),
        inInclusiveRange(minute - 1, minute),
      );
    }
    expect(scale.minuteAt(-5), 0);
    expect(scale.minuteAt(scale.total + 10), 24 * 60);
  });
}

void dragSpanTests() {
  test('drag picks quarter hours, either direction, at least 15 minutes', () {
    expect(dragSpan(9 * 60 + 5, 10 * 60 + 40), (
      start: 9 * 60,
      end: 10 * 60 + 45,
    ));
    expect(dragSpan(11 * 60, 10 * 60 + 20), (
      start: 10 * 60 + 15,
      end: 11 * 60,
    ));
    expect(dragSpan(14 * 60, 14 * 60 + 5), (start: 14 * 60, end: 14 * 60 + 15));
    expect(dragSpan(23 * 60 + 55, 24 * 60), (
      start: 23 * 60 + 45,
      end: 24 * 60,
    ));
  });
}

void mergeStatusTests() {
  AgendaSourceEvent copy(
    String calendar, {
    String title = 'TNG Meeting',
    bool unanswered = false,
    bool answered = false,
  }) => AgendaSourceEvent(
    instanceId: '$calendar-1',
    calendarId: calendar,
    title: title,
    start: DateTime(2026, 10, 13, 11),
    end: DateTime(2026, 10, 13, 12),
    allDay: false,
    unanswered: unanswered,
    answered: answered,
  );
  const calendars = [
    AgendaCalendar(id: 'exchange', name: 'k2473476', accountName: 'kcl'),
    AgendaCalendar(id: 'outlook', name: 'Calendario', accountName: 'kcl'),
  ];

  test('an Exchange copy without status keeps the Outlook "unanswered"', () {
    final entries = mergeAgendaEntries(
      events: [copy('exchange'), copy('outlook', unanswered: true)],
      calendars: calendars,
      hiddenCalendarIds: const {},
    );
    expect(entries.single.unanswered, isTrue);
    expect(entries.single.calendarIds, ['exchange', 'outlook']);
  });

  test('a copy with an answer wins', () {
    final entries = mergeAgendaEntries(
      events: [
        copy('exchange', answered: true),
        copy('outlook', unanswered: true),
      ],
      calendars: calendars,
      hiddenCalendarIds: const {},
    );
    expect(entries.single.unanswered, isFalse);
  });

  test('the unanswered filter hides the merged entry, not one copy', () {
    final entries = mergeAgendaEntries(
      events: [copy('exchange'), copy('outlook', unanswered: true)],
      calendars: calendars,
      hiddenCalendarIds: const {},
      filter: const AgendaFilter(hideUnanswered: true),
    );
    expect(entries, isEmpty);
  });

  test('meetings left as "Canceled:" by Exchange are hidden', () {
    for (final title in [
      'Canceled: TNG Meeting',
      'Cancelled: Lab',
      'Annullato: Riunione',
      '  canceled : x',
    ]) {
      expect(isCanceledTitle(title), isTrue, reason: title);
    }
    expect(isCanceledTitle('Canceled flights review'), isFalse);
    expect(isCanceledTitle('Review: cancelled items'), isFalse);
    final entries = mergeAgendaEntries(
      events: [copy('exchange', title: 'Canceled: TNG Meeting')],
      calendars: calendars,
      hiddenCalendarIds: const {},
    );
    expect(entries, isEmpty);
  });
}

void holidayTests() {
  AgendaCalendar cal(String id, String name) =>
      AgendaCalendar(id: id, name: name, accountName: 'a');
  test('holiday calendars are recognised by name', () {
    for (final name in [
      'Holidays in Italy',
      'Festività in Italia',
      'Festività ebraiche',
      'United Kingdom holidays',
      'Holidays in Switzerland',
      '공휴일',
      '법정기념일',
    ]) {
      expect(isHolidayCalendar(cal('x', name)), isTrue, reason: name);
    }
    for (final name in ['Calendario', 'Compleanni', 'SLAM', '✨ Assistente']) {
      expect(isHolidayCalendar(cal('x', name)), isFalse, reason: name);
    }
  });

  test('hiding holidays wins over an explicit choice', () {
    final calendars = [cal('h', 'Holidays in Italy'), cal('k', 'Calendario')];
    final choices = {'h': true, 'k': true};
    expect(hiddenAgendaCalendars(calendars, choices), isEmpty);
    expect(hiddenAgendaCalendars(calendars, choices, hideHolidays: true), {
      'h',
    });
    expect(const AgendaFilter().hideHolidays, isTrue);
    expect(AgendaFilter.none.isActive, isFalse);
  });
}
