import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_event_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// "Nascondi in Todo" and Todo's own calendar (build 226): nothing here may
// require writing to the calendar an event comes from.

const kcl = AgendaCalendar(id: 'kcl', name: 'Calendar', accountName: 'kcl');
const slam = AgendaCalendar(id: 'slam', name: 'Calendar', accountName: 'slam');
const todo = AgendaCalendar(
  id: 'todo',
  name: AgendaService.localCalendarName,
  accountName: AgendaService.localAccountName,
  writable: true,
  localOnly: true,
);

AgendaSourceEvent _event(
  String id,
  String calendar,
  String title,
  int day, {
  int hour = 9,
}) => AgendaSourceEvent(
  instanceId: id,
  calendarId: calendar,
  title: title,
  start: DateTime(2026, 10, day, hour),
  end: DateTime(2026, 10, day, hour + 1),
  allDay: false,
);

List<AgendaEntry> _merge(List<AgendaSourceEvent> events, AgendaFilter filter) =>
    mergeAgendaEntries(
      events: events,
      calendars: const [kcl, slam, todo],
      hiddenCalendarIds: const {},
      filter: filter,
    );

HiddenAgendaEvent _hidden(String key) => HiddenAgendaEvent(
  key: key,
  title: 'x',
  start: DateTime(2026, 10, 6),
  allDay: false,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('hiding a merged meeting hides every copy, nothing else', () {
    final events = [
      _event('k1', 'kcl', 'Ward round', 6),
      _event('s1', 'slam', 'Ward round', 6),
      _event('k2', 'kcl', 'Ward round', 7),
    ];
    final entries = _merge(events, const AgendaFilter());
    expect(entries, hasLength(2));
    final filter = const AgendaFilter().hiding(
      HiddenAgendaEvent(
        key: entries.first.key,
        title: entries.first.title,
        start: entries.first.start,
        allDay: false,
      ),
      DateTime(2026, 10, 5),
    );
    expect([for (final e in _merge(events, filter)) e.instanceId], ['k2']);
    expect(_merge(events, filter.showing(entries.first.key)), hasLength(2));
  });

  test('a series hidden by title spares the copies edited in Todo', () {
    final events = [
      _event('k1', 'kcl', 'Weekly MDT', 6),
      _event('k2', 'kcl', 'weekly mdt ', 13),
      _event('t1', 'todo', 'Weekly MDT', 20),
    ];
    final filter = const AgendaFilter().hiding(
      _hidden(agendaTitleKey('Weekly MDT')),
      DateTime(2026, 10, 5),
    );
    expect([for (final e in _merge(events, filter)) e.instanceId], ['t1']);
  });

  test('a copy in Todo never merges with the original it replaces', () {
    final events = [
      _event('k1', 'kcl', 'Ward round', 6),
      _event('t1', 'todo', 'Ward round', 6),
    ];
    final entries = _merge(events, const AgendaFilter());
    expect(entries, hasLength(2));
    final original = entries.firstWhere((e) => e.instanceId == 'k1');
    final filter = const AgendaFilter().hiding(
      _hidden(original.key),
      DateTime(2026, 10, 5),
    );
    expect([for (final e in _merge(events, filter)) e.instanceId], ['t1']);
  });

  test('old single occurrences are pruned, series are kept', () {
    final now = DateTime(2027, 12, 1);
    final filter = AgendaFilter(
      hiddenEvents: [
        HiddenAgendaEvent(
          key: 'old',
          title: 'Old',
          start: DateTime(2026, 1, 1),
          allDay: false,
        ),
        HiddenAgendaEvent(
          key: agendaTitleKey('Old series'),
          title: 'Old series',
          start: DateTime(2026, 1, 1),
          allDay: false,
        ),
      ],
    ).hiding(_hidden('new'), now);
    expect(
      [for (final h in filter.hiddenEvents) h.key],
      [agendaTitleKey('Old series'), 'new'],
    );
  });

  test('hidden events survive saving and reading the filter', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = AgendaService(db);
    final entry = _merge([
      _event('k1', 'kcl', 'Ward round', 6),
    ], const AgendaFilter()).single;
    await service.hideEvent(entry);
    await service.hideEvent(entry, series: true);
    final read = await AgendaService(db).filter();
    expect(
      [for (final h in read.hiddenEvents) h.key],
      [entry.key, agendaTitleKey('Ward round')],
    );
    expect(read.hideHolidays, isTrue);
    await service.showHiddenEvent(entry.key);
    expect((await AgendaService(db).filter()).hiddenEvents, hasLength(1));
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool editable,
    required bool localOnly,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AgendaEventSheet(
          entry: AgendaEntry(
            instanceId: 'k1',
            calendarIds: const ['kcl'],
            title: 'Ward round',
            start: DateTime(2026, 10, 6, 9),
            end: DateTime(2026, 10, 6, 10),
            allDay: false,
          ),
          calendarName: 'KCL',
          editable: editable,
          zoneLabel: null,
          localOnly: localOnly,
          canCopyInTodo: true,
        ),
      ),
    ),
  );

  testWidgets('an invitation of someone else can still be hidden or edited '
      'in Todo', (tester) async {
    await pumpSheet(tester, editable: false, localOnly: false);
    expect(find.byKey(const ValueKey('agenda-sheet-hide')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agenda-sheet-edit-in-todo')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agenda-sheet-delete')), findsNothing);
  });

  testWidgets('own calendar events: original actions are named as such', (
    tester,
  ) async {
    await pumpSheet(tester, editable: true, localOnly: false);
    expect(find.text('Elimina dal calendario'), findsOneWidget);
    expect(find.text('Modifica nel calendario'), findsOneWidget);
  });

  testWidgets('Todo events are edited and deleted directly', (tester) async {
    await pumpSheet(tester, editable: true, localOnly: true);
    expect(find.text('Elimina'), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-sheet-hide')), findsNothing);
    expect(
      find.byKey(const ValueKey('agenda-sheet-edit-in-todo')),
      findsNothing,
    );
    expect(find.textContaining('Solo in Todo'), findsOneWidget);
  });
}
