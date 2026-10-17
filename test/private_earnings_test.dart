import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/private_earnings.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/private_earnings_service.dart';
import 'package:deterministic_todo/ui/private_earnings_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final now = DateTime(2026, 10, 12, 18);
AgendaEntry entry(
  String title,
  int minutes, {
  DateTime? start,
  String id = '1',
  bool allDay = false,
  bool unanswered = false,
  String? taskId,
}) {
  final at = start ?? DateTime(2026, 10, 5, 10);
  return AgendaEntry(
    instanceId: id,
    calendarIds: const ['private'],
    title: title,
    start: at,
    end: at.add(Duration(minutes: minutes)),
    allDay: allDay,
    unanswered: unanswered,
    taskId: taskId,
  );
}

class _Agenda extends AgendaService {
  _Agenda(super.database);
  AgendaAccess permission = AgendaAccess.granted;
  bool fail = false;
  int reads = 0;
  DateTime? from;
  DateTime? until;
  List<String>? ids;
  List<AgendaCalendar> sources = const [
    AgendaCalendar(id: 'private', name: 'Semble', accountName: ''),
    AgendaCalendar(id: 'copy', name: 'heydoc', accountName: ''),
    AgendaCalendar(id: 'other', name: 'Other work', accountName: ''),
  ];
  @override
  Future<AgendaAccess> access() async => permission;
  @override
  Future<List<AgendaCalendar>> calendars() async => sources;
  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    reads++;
    from = start;
    until = end;
    ids = calendarIds;
    if (fail) throw StateError('Synthetic provider failure');
    return [
      for (final id in ['private', 'copy'])
        AgendaSourceEvent(
          instanceId: id,
          calendarId: id,
          title: 'Follow-up',
          start: DateTime(2026, 10, 5, 10),
          end: DateTime(2026, 10, 5, 10, 15),
          allDay: false,
        ),
      AgendaSourceEvent(
        instanceId: 'scheduled',
        calendarId: 'private',
        title: 'Prima visita',
        start: DateTime(2026, 10, 20, 10),
        end: DateTime(2026, 10, 20, 11),
        allDay: false,
      ),
      AgendaSourceEvent(
        instanceId: 'canceled',
        calendarId: 'private',
        title: 'Prima visita',
        start: DateTime(2026, 10, 6, 10),
        end: DateTime(2026, 10, 6, 11),
        allDay: false,
        canceled: true,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('it'));

  test('fee schedule and conservative unknowns', () {
    final cases = <(String, int, PrivateFee?)>[
      ('Prima visita adulti', 60, PrivateFee.initial),
      ('Initial consultation C&A', 90, PrivateFee.childInitial),
      ('Initial child consultation', 60, PrivateFee.initial),
      ('Follow-up', 15, PrivateFee.followUp15),
      ('Follow up urgente', 30, PrivateFee.followUp30),
      ('Repeat prescription', 5, PrivateFee.prescription),
      ('Report', 30, PrivateFee.letter),
      ('ADHD assessment', 90, PrivateFee.adhdAssessment),
      ('ADHD diagnostic feedback', 30, PrivateFee.adhdFeedback),
      ('ADHD follow-up', 30, PrivateFee.followUp30),
      ('ADHD assessment report', 30, null),
      ('ADHD feedback report', 30, null),
      ('ASD assessment', 90, null),
      ('Synthetic person', 60, null),
      ('Appointment', 60, null),
      ('Follow-up', 45, null),
      ('Follow-up consultation 30 minutes', 45, PrivateFee.followUp30),
      ('Urgent initial adult consultation 60 min', 75, PrivateFee.initial),
      ('Follow-up 15 min / 30 min', 45, null),
      ('Follow-up 30 min', 15, null),
      ('ADHD assessment child and adolescent', 75, null),
      ('ADHD feedback child', 30, null),
      ('Prima visita', 90, null),
    ];
    for (final (title, minutes, fee) in cases) {
      expect(privateFeeFor(entry(title, minutes)), fee, reason: title);
    }
  });

  test(
    'current civil month, completed appointments only, no tasks or absences',
    () {
      final valid = entry('Follow-up', 15);
      final result = estimatePrivateEarnings([
        valid,
        valid,
        entry(
          'Prima visita',
          60,
          id: 'last-month',
          start: DateTime(2026, 9, 30, 23, 30),
        ),
        entry('Prima visita', 60, id: 'future', start: DateTime(2026, 10, 13)),
        entry(
          'Prima visita',
          60,
          id: 'ongoing',
          start: now.subtract(const Duration(minutes: 30)),
        ),
        entry('Prima visita', 60, id: 'all-day', allDay: true),
        entry('Prima visita', 60, id: 'unanswered', unanswered: true),
        entry('Prima visita', 60, id: 'task', taskId: 'task'),
        entry('Cancelled: Prima visita', 60, id: 'canceled'),
        entry('Follow-up - DNA', 30, id: 'dna'),
        entry('Unknown service', 30, id: 'unknown'),
        entry(
          'Follow-up',
          30,
          id: 'ends-now',
          start: now.subtract(const Duration(minutes: 30)),
        ),
        entry('Follow-up', 15, id: 'month-start', start: DateTime(2026, 10)),
      ], now);
      expect(result.pence, 24000);
      expect(result.visits, 3);
      expect(result.unpriced, 1);
      expect(result.scheduledPence, 34000);
      expect(result.scheduledVisits, 2);
      expect(result.monthPence, 58000);
      expect(estimatePrivateEarnings([valid], DateTime(2026, 11, 1)).pence, 0);
      expect(
        estimatePrivateEarnings([
          entry('Follow-up', 15, start: DateTime(2026, 12, 31)),
        ], DateTime(2027, 1, 1)).pence,
        0,
      );
    },
  );

  test(
    'scheduled excludes other months, canceled events and duplicate occurrences',
    () {
      final future = entry(
        'Follow-up',
        30,
        id: 'future',
        start: DateTime(2026, 10, 20),
      );
      final result = estimatePrivateEarnings([
        future,
        future,
        entry('Prima visita', 60, id: 'november', start: DateTime(2026, 11)),
        entry(
          'Prima visita',
          60,
          id: 'september',
          start: DateTime(2026, 9, 30, 23, 30),
        ),
        entry(
          'Cancelled: Prima visita',
          60,
          id: 'canceled',
          start: DateTime(2026, 10, 20),
        ),
        entry('Follow-up - DNA', 30, id: 'dna', start: DateTime(2026, 10, 20)),
        entry(
          'Unknown service',
          30,
          id: 'unknown',
          start: DateTime(2026, 10, 20),
        ),
        entry(
          'Prima visita',
          60,
          id: 'all-day',
          allDay: true,
          start: DateTime(2026, 10, 20),
        ),
        entry(
          'Prima visita',
          60,
          id: 'unanswered',
          unanswered: true,
          start: DateTime(2026, 10, 20),
        ),
        entry(
          'Follow-up',
          30,
          id: 'cross-month',
          start: DateTime(2026, 10, 31, 23, 45),
        ),
      ], now);
      expect(result.pence, 0);
      expect(result.unpriced, 0);
      expect(result.scheduledPence, 22000);
      expect(result.scheduledVisits, 2);
      expect(result.scheduledUnpriced, 1);
      expect(result.monthPence, 22000);
      final december = estimatePrivateEarnings([
        entry('Follow-up', 15, start: DateTime(2026, 12, 31, 23, 45)),
        entry('Follow-up', 30, id: 'january', start: DateTime(2027, 1)),
      ], DateTime(2026, 12, 1));
      expect(december.monthPence, 6500);
    },
  );

  test('appointment moves from scheduled to accrued exactly at its end', () {
    final appointment = entry(
      'Follow-up',
      30,
      start: DateTime(2026, 10, 12, 18),
    );
    final before = estimatePrivateEarnings([
      appointment,
    ], DateTime(2026, 10, 12, 18, 29));
    final after = estimatePrivateEarnings([
      appointment,
    ], DateTime(2026, 10, 12, 18, 30));
    expect(before.pence, 0);
    expect(before.scheduledPence, 11000);
    expect(after.pence, 11000);
    expect(after.scheduledPence, 0);
    expect(before.monthPence, after.monthPence);
  });

  test('ADHD package charged by stage without an extra report', () {
    final result = estimatePrivateEarnings([
      entry('ADHD assessment', 90),
      entry('ADHD feedback', 30, id: 'feedback'),
      entry('ADHD report', 30, id: 'report'),
    ], now);
    expect(result.pence, 30000);
    expect(result.unpriced, 1);
  });

  test(
    'provider reads only this month and private sources; exact duplicates merge',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final agenda = _Agenda(db);
      final result = await PrivateEarningsService(agenda).load(now: now);
      expect(agenda.from, DateTime(2026, 10));
      expect(agenda.until, DateTime(2026, 11));
      expect(agenda.ids, ['private', 'copy']);
      expect(agenda.reads, 1);
      expect(result.pence, 6500);
      expect(result.visits, 1);
      expect(result.scheduledPence, 17000);
      expect(result.monthPence, 23500);
    },
  );

  test(
    'missing permissions or calendars never masquerade as zero income',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final agenda = _Agenda(db)..permission = AgendaAccess.denied;
      final service = PrivateEarningsService(agenda);
      await expectLater(
        service.load(now: now),
        throwsA(isA<PrivateEarningsUnavailable>()),
      );
      agenda.permission = AgendaAccess.granted;
      agenda.sources = [];
      await expectLater(
        service.load(now: now),
        throwsA(isA<PrivateEarningsUnavailable>()),
      );
      expect(agenda.reads, 0);
    },
  );

  testWidgets(
    'sheet shows named month, estimate, counts and a safe retry error',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final agenda = _Agenda(db);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateEarningsSheet(service: _FixedService(agenda)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lavoro privato · ottobre'), findsOneWidget);
      expect(find.text('£65.00'), findsOneWidget);
      expect(find.text('Maturato finora'), findsOneWidget);
      expect(find.text('Totale previsto del mese'), findsOneWidget);
      expect(find.text('£235.00'), findsOneWidget);
      expect(find.textContaining('Finora + £170.00'), findsOneWidget);
      expect(find.textContaining('Importi lordi stimati'), findsOneWidget);
      await tester.ensureVisible(find.text('Ancora programmati'));
      await tester.tap(find.text('Ancora programmati'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 × Prima visita'), findsOneWidget);
      agenda.fail = true;
      await tester.ensureVisible(find.text('Aggiorna'));
      await tester.tap(find.text('Aggiorna'));
      await tester.pumpAndSettle();
      expect(
        find.text('Stima non disponibile. Riprova tra poco.'),
        findsOneWidget,
      );
      expect(find.text('£65.00'), findsNothing);
      expect(find.text('£235.00'), findsNothing);
      expect(find.textContaining('Synthetic provider failure'), findsNothing);
    },
  );
}

class _FixedService extends PrivateEarningsService {
  _FixedService(super.agenda);
  @override
  Future<PrivateEarnings> load({DateTime? now}) =>
      super.load(now: DateTime(2026, 10, 12, 18));
}
