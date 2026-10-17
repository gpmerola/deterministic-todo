import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_reminders.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/agenda_urgent_visits.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Calendar extends AgendaService {
  _Calendar(super.database);
  AgendaAccess permission = AgendaAccess.granted;
  int reads = 0;
  DateTime? rangeEnd;
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
  ) async {
    reads++;
    rangeEnd = end;
    return rows.where((e) => ids.contains(e.calendarId)).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual title formats, whole words, case and explicit negations', () {
    for (final title in [
      'Prima visita urgente',
      'Follow-up urgente',
      'Synthetic — Urgent Consultation',
      'VISITE URGENTI',
      'Urgent assessment',
    ]) {
      expect(isUrgentVisitTitle(title), isTrue, reason: title);
    }
    for (final title in [
      'Visita ordinaria',
      'Follow-up',
      'Urgent task',
      'Visita non urgente',
      'Non-urgent consultation',
      'Not urgent appointment',
      'Visita urgentemente',
      'Visita urgente — non urgente',
    ]) {
      expect(isUrgentVisitTitle(title), isFalse, reason: title);
    }
  });

  test(
    'time bounds, tasks, duplicates and title changes preserve identity',
    () {
      final now = DateTime(2026, 10, 11, 12);
      AgendaEntry entry({
        String title = 'Visita urgente',
        DateTime? end,
        String? taskId,
        bool allDay = false,
      }) => AgendaEntry(
        instanceId: '1@123',
        calendarIds: const ['1'],
        title: title,
        start: now,
        end: end ?? now.add(const Duration(hours: 1)),
        allDay: allDay,
        taskId: taskId,
      );
      final until = now.add(const Duration(days: 90));
      final plan = urgentVisitPlan(
        [
          entry(),
          entry(),
          entry(taskId: 'todo'),
          entry(end: now),
          entry(title: 'Visita ordinaria'),
        ],
        now,
        until,
      );
      expect(plan, hasLength(1));
      expect(plan.single.keys, unorderedEquals(['id', 'start', 'end']));
      expect(
        urgentVisitPlan(
          [entry(title: 'Visita urgente aggiornata')],
          now,
          until,
        ).single['id'],
        plan.single['id'],
      );
      expect(urgentVisitPlan([entry(allDay: true)], now, until), hasLength(1));
      expect(urgentVisitPlan([entry()], now, now), isEmpty);
    },
  );

  test(
    'fresh filters, merged copies, revoked access and overlapping resumes',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final service = _Calendar(db);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AgendaReminders.channel, (call) async {
            calls.add(call);
            return 1;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AgendaReminders.channel, null);
        await db.close();
      });
      final start = DateTime.now().add(const Duration(days: 30));
      AgendaSourceEvent row(
        String id, {
        String calendar = '1',
        String title = 'Visita urgente',
        bool canceled = false,
      }) => AgendaSourceEvent(
        instanceId: id,
        calendarId: calendar,
        title: title,
        start: start,
        end: start.add(const Duration(hours: 1)),
        allDay: false,
        canceled: canceled,
      );
      service.rows = [
        row('1'),
        row('2', calendar: '2'),
        row('3', title: 'Follow-up urgente', canceled: true),
        row('4', title: 'Visita non urgente'),
      ];
      await Future.wait([
        AgendaUrgentVisits(service).foreground(),
        AgendaUrgentVisits(service).foreground(),
      ]);
      expect(service.reads, 1);
      expect(calls.single.method, 'notifyUrgentVisits');
      expect((calls.single.arguments as Map)['events'], hasLength(1));
      expect(service.rangeEnd!.isAfter(start), isTrue);
      await service.saveFilter(const AgendaFilter(hiddenWords: ['urgente']));
      await AgendaUrgentVisits(service).foreground();
      expect((calls.last.arguments as Map)['events'], isEmpty);
      await service.saveFilter(AgendaFilter.none);
      await service.saveCalendarChoices({'1': false, '2': false});
      await AgendaUrgentVisits(service).foreground();
      expect((calls.last.arguments as Map)['events'], isEmpty);
      final count = calls.length;
      service.permission = AgendaAccess.denied;
      await AgendaUrgentVisits(service).foreground();
      expect(calls, hasLength(count));
    },
  );
}
