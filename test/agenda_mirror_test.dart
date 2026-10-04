import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_mirror.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/agenda_web_service.dart';
import 'package:deterministic_todo/ui/views/agenda_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const first = CivilDate(2026, 10, 5);
const calendar = AgendaCalendar(
  id: 'cal',
  name: 'Personale',
  accountName: 'me@example.com',
  colorHex: '#039BE5',
  writable: true,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('la copia contiene ogni evento una volta, senza attività', () {
    final days = buildAgenda(
      events: [
        AgendaSourceEvent(
          instanceId: 'night',
          calendarId: 'cal',
          title: 'Turno',
          start: DateTime(2026, 10, 5, 22),
          end: DateTime(2026, 10, 6, 2),
          allDay: false,
          description: 'https://teams.microsoft.com/l/meetup-join/x',
        ),
        AgendaSourceEvent(
          instanceId: 'congress',
          calendarId: 'cal',
          title: 'Congresso',
          start: DateTime(2026, 10, 6),
          end: DateTime(2026, 10, 8),
          allDay: true,
        ),
      ],
      tasks: const [
        AgendaTaskItem(id: 't', title: 'Slide', date: CivilDate(2026, 10, 5)),
      ],
      calendars: const [calendar],
      hiddenCalendarIds: const {},
      first: first,
      days: 3,
    );
    final payload = buildAgendaMirror(
      days: days,
      calendars: const [calendar],
      first: first,
      count: 3,
      deviceId: 'device',
      zoneLabel: 'Europe/London · UTC+1',
      taskLinks: {'task:t', 'series:s'},
    );
    final events = payload['events']! as List<Map<String, Object?>>;
    // The night shift spans two days but is sent once; the task is not sent.
    expect(events.map((e) => e['instance_key']), ['night', 'congress']);
    expect(
      events.first['starts_at'],
      DateTime(2026, 10, 5, 22).toUtc().toIso8601String(),
    );
    expect(events.first['meeting_provider'], 'Teams');
    expect(events.last['start_date'], '2026-10-06');
    expect(events.last['end_date'], '2026-10-08');
    expect(events.first.containsKey('start_date'), isFalse);
    expect(payload['task_links'], ['series:s', 'task:t']);
    expect(payload['calendars'], [
      {
        'key': 'cal',
        'name': 'Personale',
        'account': 'me@example.com',
        'color': '#039BE5',
      },
    ]);
    expect(
      payload['window_end'],
      first.addDays(3).asLocalDate.toUtc().toIso8601String(),
    );
  });

  test('sul Web le righe tornano eventi, giornate intere comprese', () {
    final timed = WebAgendaService.fromRow({
      'instance_key': 'e1',
      'calendar_keys': ['cal', 'other'],
      'title': 'TNG',
      'starts_at': '2026-10-08T14:30:00Z',
      'ends_at': '2026-10-08T15:30:00Z',
      'all_day': false,
      'meeting_url': 'https://teams.microsoft.com/l/meetup-join/x',
      'is_organizer': false,
    });
    expect(timed.calendarId, 'cal');
    expect(timed.start, DateTime.utc(2026, 10, 8, 14, 30).toLocal());
    expect(findMeetingLink(timed)?.provider, 'Teams');
    expect(timed.isOrganizer, isFalse);
    final allDay = WebAgendaService.fromRow({
      'instance_key': 'e2',
      'calendar_keys': ['cal'],
      'title': 'Congresso',
      'starts_at': '2026-10-05T23:00:00Z',
      'ends_at': '2026-10-07T23:00:00Z',
      'all_day': true,
      'start_date': '2026-10-06',
      'end_date': '2026-10-08',
    });
    expect(allDay.start, DateTime(2026, 10, 6));
    expect(allDay.end, DateTime(2026, 10, 8));
  });

  testWidgets('sul Web l Agenda è in sola lettura', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _ReadOnlyService(db);
    await service.saveViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-new-event')), findsNothing);
    expect(
      find.textContaining('Copia dal telefono · 5 ott 09:00'),
      findsOneWidget,
    );
    await tester.tap(find.text('Riunione'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-sheet-edit')), findsNothing);
    expect(find.byKey(const ValueKey('agenda-sheet-delete')), findsNothing);
    expect(find.text('Apri nel calendario'), findsNothing);
    expect(find.textContaining('Sola lettura sul Web'), findsOneWidget);
  });

  testWidgets('senza copia spiega cosa fare', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _ReadOnlyService(db)..mirrored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('copia inviata dal telefono'), findsOneWidget);
  });
}

class _ReadOnlyService extends AgendaService {
  _ReadOnlyService(super.database);
  bool mirrored = true;

  @override
  bool get canWrite => false;

  @override
  String? get mirrorLabel => 'Copia dal telefono · 5 ott 09:00';

  @override
  Future<AgendaAccess> access() async =>
      mirrored ? AgendaAccess.granted : AgendaAccess.noMirror;

  @override
  Future<String?> deviceZoneLabel() async =>
      lastZoneLabel = 'Europe/London · UTC+1';

  @override
  Future<List<AgendaCalendar>> calendars() async => lastCalendars = const [
    AgendaCalendar(id: 'cal', name: 'Personale', accountName: ''),
  ];

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async => [
    AgendaSourceEvent(
      instanceId: 'r',
      calendarId: 'cal',
      title: 'Riunione',
      start: DateTime(2026, 10, 5, 11),
      end: DateTime(2026, 10, 5, 12),
      allDay: false,
    ),
  ];
}
