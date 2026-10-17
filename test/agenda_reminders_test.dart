import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_reminders.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_reminder_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Calendar extends AgendaService {
  _Calendar(super.database);
  AgendaAccess permission = AgendaAccess.granted;
  List<AgendaSourceEvent> rows = [];
  @override
  Future<AgendaAccess> access() async => permission;
  @override
  Future<List<AgendaCalendar>> calendars() async => const [
    AgendaCalendar(id: '1', name: 'Synthetic', accountName: ''),
    AgendaCalendar(id: '2', name: 'Other', accountName: ''),
  ];
  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> ids,
  ) async => rows.where((row) => ids.contains(row.calendarId)).toList();
}

AgendaSourceEvent _source(
  String id,
  DateTime start, {
  String calendar = '1',
  String title = 'Synthetic',
  bool allDay = false,
}) => AgendaSourceEvent(
  instanceId: id,
  calendarId: calendar,
  title: title,
  start: start,
  end: start.add(const Duration(hours: 1)),
  allDay: allDay,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _Calendar service;
  late AgendaReminders reminders;
  late List<MethodCall> calls;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = _Calendar(db);
    reminders = AgendaReminders(service);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AgendaReminders.channel, (call) async {
          calls.add(call);
          if (call.method == 'beginReminders') return 1;
          if (call.method == 'reminderStatus') {
            return {'notifications': false, 'exact': false};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AgendaReminders.permissions,
          (_) async => null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AgendaReminders.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AgendaReminders.permissions, null);
    await db.close();
  });

  test(
    'enabled by default, disabled choice persists and clears native queue',
    () async {
      expect(await reminders.enabled(), isTrue);
      await reminders.setEnabled(false);
      expect(await AgendaReminders(service).enabled(), isFalse);
      expect((calls.last.arguments as Map)['enabled'], isFalse);
      expect((calls.last.arguments as Map)['events'], isEmpty);
      await reminders.setEnabled(true);
      expect(await reminders.enabled(), isTrue);
    },
  );

  test(
    'existing events, deduplication, recurring instances and day boundaries',
    () async {
      final start = DateTime.now().add(const Duration(days: 1));
      service.rows = [
        _source('10@100', start),
        _source('20@100', start, calendar: '2'),
        _source('10@200', start.add(const Duration(days: 1))),
        _source('30', start, allDay: true),
        _source('40', DateTime.now().subtract(const Duration(days: 1))),
      ];
      await reminders.refresh();
      final plan = ((calls.last.arguments as Map)['events'] as List)
          .cast<Map>();
      expect(plan, hasLength(2));
      expect(
        plan.first['at'],
        start.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );
      expect(plan.first['eventId'], '10');
      expect(plan.first['id'], isNot(plan.last['id']));
    },
  );

  test('fresh filters and calendar choices cancel pending reminders', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    service.rows = [
      _source('1', start),
      _source('2', start, calendar: '2', title: 'Hidden'),
    ];
    await service.saveFilter(const AgendaFilter(hiddenWords: ['Hidden']));
    await reminders.refresh();
    expect((calls.last.arguments as Map)['events'], hasLength(1));
    await service.saveCalendarChoices({'1': false});
    await reminders.refresh();
    expect((calls.last.arguments as Map)['events'], isEmpty);
  });

  test(
    'revoked calendar access clears alarms without querying events',
    () async {
      service.permission = AgendaAccess.denied;
      await reminders.refresh();
      expect((calls.last.arguments as Map)['accessible'], isFalse);
      expect((calls.last.arguments as Map)['events'], isEmpty);
    },
  );

  test(
    'planner uses instants across DST and deduplicates multi-day display',
    () {
      final start = DateTime.parse('2026-10-25T01:10:00Z');
      final event = AgendaEntry(
        instanceId: '1',
        calendarIds: const ['1'],
        title: 'Synthetic',
        start: start,
        end: start.add(const Duration(days: 2)),
        allDay: false,
      );
      final plan = reminderPlan([event, event], DateTime.utc(2026, 10, 24));
      expect(plan, hasLength(1));
      expect(
        plan.single['at'],
        DateTime.parse('2026-10-25T00:40:00Z').millisecondsSinceEpoch,
      );
    },
  );

  testWidgets(
    'switch is on by default, explains OS permission and persists off',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgendaReminderSheet(reminders: reminders)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(find.text('Consenti in Android'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(await reminders.enabled(), isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.text('Consenti in Android'), findsNothing);
    },
  );
}
