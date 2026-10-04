import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/agenda_request.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_phone_sync.dart';
import 'package:deterministic_todo/services/agenda_requests.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/agenda_web_service.dart';
import 'package:deterministic_todo/ui/views/agenda_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AgendaRequest _request(
  AgendaRequestKind kind, {
  String id = 'r1',
  String? key,
  bool series = false,
  Map<String, Object?> payload = const {},
  AgendaRequestStatus status = AgendaRequestStatus.pending,
  String? error,
}) => AgendaRequest(
  id: id,
  kind: kind,
  status: status,
  createdAt: DateTime.utc(2026, 10, 5, 8),
  instanceKey: key,
  series: series,
  payload: payload,
  error: error,
);

AgendaSourceEvent _event(String id, {String title = 'Riunione', int day = 6}) =>
    AgendaSourceEvent(
      instanceId: id,
      calendarId: 'cal',
      title: title,
      start: DateTime(2026, 10, day, 9),
      end: DateTime(2026, 10, day, 10),
      allDay: false,
    );

final _timed = AgendaEventDraft(
  calendarId: 'cal',
  title: ' Visita ',
  start: DateTime(2026, 10, 8, 15),
  end: DateTime(2026, 10, 8, 16),
  location: 'Maudsley',
  notes: 'Portare referto',
  repeat: AgendaRepeat.weekly,
  repeatUntil: const CivilDate(2026, 12, 31),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('payload', () {
    test('a timed creation travels as UTC and comes back local', () {
      final payload = agendaRequestPayload(_timed, create: true);
      expect(
        payload['start'],
        DateTime(2026, 10, 8, 15).toUtc().toIso8601String(),
      );
      expect(payload['title'], 'Visita');
      expect(payload['notes'], 'Portare referto');
      expect(payload['repeat'], 'weekly');
      expect(payload['repeat_until'], '2026-12-31');
      final back = draftFromAgendaPayload(payload)!;
      expect(back.start, DateTime(2026, 10, 8, 15));
      expect(back.end, DateTime(2026, 10, 8, 16));
      expect(back.repeat, AgendaRepeat.weekly);
      expect(back.repeatUntil, const CivilDate(2026, 12, 31));
      expect(back.location, 'Maudsley');
    });

    test('an edit carries no notes and no repetition', () {
      final payload = agendaRequestPayload(_timed, create: false);
      expect(payload.containsKey('notes'), isFalse);
      expect(payload.containsKey('repeat'), isFalse);
    });

    test('all-day spans travel as civil dates', () {
      final payload = agendaRequestPayload(
        AgendaEventDraft(
          calendarId: 'cal',
          title: 'Congresso',
          start: DateTime(2026, 11, 12),
          end: DateTime(2026, 11, 14),
          allDay: true,
        ),
        create: true,
      );
      expect(payload['start_date'], '2026-11-12');
      expect(payload['end_date'], '2026-11-14');
      expect(payload.containsKey('start'), isFalse);
      final back = draftFromAgendaPayload(payload)!;
      expect(back.start, DateTime(2026, 11, 12));
      expect(back.end, DateTime(2026, 11, 14));
      expect(back.allDay, isTrue);
    });

    test('malformed payloads are refused, not guessed', () {
      expect(draftFromAgendaPayload(const {}), isNull);
      expect(
        draftFromAgendaPayload(const {'start': 'ieri', 'end': 'x'}),
        isNull,
      );
      expect(
        draftFromAgendaPayload(const {
          'start': '2026-10-08T14:00:00Z',
          'end': '2026-10-08T15:00:00Z',
          'repeat': 'hourly',
        }),
        isNull,
      );
    });

    test('rows from Supabase', () {
      final request = AgendaRequest.fromRow({
        'id': 'r9',
        'kind': 'update',
        'status': 'failed',
        'created_at': '2026-10-05T08:00:00Z',
        'completed_at': '2026-10-05T08:05:00Z',
        'instance_key': '42@1',
        'series': true,
        'payload': {'title': 'TNG'},
        'error': 'Calendario in sola lettura.',
      });
      expect(request.kind, AgendaRequestKind.update);
      expect(request.status, AgendaRequestStatus.failed);
      expect(request.open, isFalse);
      expect(request.series, isTrue);
      expect(agendaRequestLabel(request), 'Modifica di «TNG»');
    });
  });

  group('web preview of queued changes', () {
    test('creations appear with ⏳, deletions disappear', () {
      final result = applyAgendaRequests(
        [_event('1'), _event('2', title: 'Pranzo')],
        [
          _request(
            AgendaRequestKind.create,
            id: 'new',
            payload: agendaRequestPayload(_timed, create: true),
          ),
          _request(AgendaRequestKind.delete, id: 'd', key: '2'),
        ],
      );
      expect(result.map((e) => e.instanceId), ['1', 'req:new']);
      expect(result.last.title, '⏳ Visita');
      expect(pendingRequestId(result.last.instanceId), 'new');
      expect(pendingRequestId('1'), isNull);
    });

    test('changes apply in queue order whatever the row order', () {
      AgendaRequest rename(String id, String title, int minute) =>
          AgendaRequest(
            id: id,
            kind: AgendaRequestKind.update,
            status: AgendaRequestStatus.pending,
            createdAt: DateTime.utc(2026, 10, 5, 8, minute),
            instanceKey: '1',
            payload: agendaRequestPayload(
              AgendaEventDraft(
                calendarId: 'cal',
                title: title,
                start: DateTime(2026, 10, 6, 9),
                end: DateTime(2026, 10, 6, 10),
              ),
              create: false,
            ),
          );
      // PostgREST returned them newest first (build 213 web test).
      final result = applyAgendaRequests(
        [_event('1')],
        [rename('b', 'Seconda', 2), rename('a', 'Prima', 1)],
      );
      expect(result.single.title, '⏳ Seconda');
    });

    test('a series deletion hides every mirrored occurrence', () {
      final result = applyAgendaRequests(
        [_event('7@1'), _event('7@2', day: 13), _event('8@1')],
        [_request(AgendaRequestKind.delete, key: '7@2', series: true)],
      );
      expect(result.map((e) => e.instanceId), ['8@1']);
    });

    test('an edit moves its occurrence; a series edit renames the rest', () {
      final moved = AgendaEventDraft(
        calendarId: 'cal',
        title: 'Supervisione',
        start: DateTime(2026, 10, 6, 11),
        end: DateTime(2026, 10, 6, 12),
      );
      final result = applyAgendaRequests(
        [_event('7@1'), _event('7@2', day: 13)],
        [
          _request(
            AgendaRequestKind.update,
            key: '7@1',
            series: true,
            payload: agendaRequestPayload(moved, create: false),
          ),
        ],
      );
      expect(result.first.title, '⏳ Supervisione');
      expect(result.first.start, DateTime(2026, 10, 6, 11));
      expect(result.last.title, '⏳ Supervisione');
      expect(result.last.start, DateTime(2026, 10, 13, 9));
    });
  });

  group('phone applies requests', () {
    late AppDatabase db;
    late _FakePhone phone;
    late AgendaRequestProcessor processor;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      phone = _FakePhone(db);
      processor = AgendaRequestProcessor(
        service: phone,
        client: SupabaseClient('http://localhost:1', 'test-key'),
      );
    });
    tearDown(() => db.close());

    test('a creation is written like one made in Agenda', () async {
      await processor.apply(
        _request(
          AgendaRequestKind.create,
          payload: agendaRequestPayload(_timed, create: true),
        ),
      );
      expect(phone.created.single.title, 'Visita');
      expect(phone.created.single.repeat, AgendaRepeat.weekly);
    });

    test('read-only or unknown calendars are refused with a reason', () async {
      Future<String?> reason(String calendar) async {
        try {
          await processor.apply(
            _request(
              AgendaRequestKind.create,
              payload: agendaRequestPayload(
                AgendaEventDraft(
                  calendarId: calendar,
                  title: 'X',
                  start: DateTime(2026, 10, 8, 9),
                  end: DateTime(2026, 10, 8, 10),
                ),
                create: true,
              ),
            ),
          );
          return null;
        } on AgendaRequestRejected catch (rejected) {
          return rejected.message;
        }
      }

      expect(await reason('shared'), 'Calendario in sola lettura.');
      expect(await reason('gone'), 'Calendario non più sul telefono.');
      expect(phone.created, isEmpty);
    });

    test('invalid drafts are refused', () async {
      await expectLater(
        processor.apply(
          _request(
            AgendaRequestKind.create,
            payload: {
              ...agendaRequestPayload(_timed, create: true),
              'title': '  ',
            },
          ),
        ),
        throwsA(isA<AgendaRequestRejected>()),
      );
    });

    test('an edit keeps the phone calendar and notes', () async {
      phone.existing['42@1'] = AgendaEventDraft(
        calendarId: 'cal',
        title: 'TNG',
        start: DateTime(2026, 10, 8, 14),
        end: DateTime(2026, 10, 8, 15),
        notes: 'Agenda riservata',
      );
      await processor.apply(
        _request(
          AgendaRequestKind.update,
          key: '42@1',
          series: true,
          payload: agendaRequestPayload(
            AgendaEventDraft(
              calendarId: 'other',
              title: 'TNG spostata',
              start: DateTime(2026, 10, 8, 16),
              end: DateTime(2026, 10, 8, 17),
            ),
            create: false,
          ),
        ),
      );
      final (id, draft, series) = phone.updated.single;
      expect(id, '42@1');
      expect(series, isTrue);
      expect(draft.calendarId, 'cal');
      expect(draft.notes, 'Agenda riservata');
      expect(draft.title, 'TNG spostata');
      expect(draft.start, DateTime(2026, 10, 8, 16));
    });

    test('editing a vanished event is refused; deleting it is done', () async {
      await expectLater(
        processor.apply(
          _request(
            AgendaRequestKind.update,
            key: 'gone',
            payload: agendaRequestPayload(_timed, create: false),
          ),
        ),
        throwsA(isA<AgendaRequestRejected>()),
      );
      await processor.apply(_request(AgendaRequestKind.delete, key: 'gone'));
      expect(phone.deleted, isEmpty);
    });

    test('a deletion removes the occurrence or the series', () async {
      phone.existing['9'] = AgendaEventDraft(
        calendarId: 'cal',
        title: 'A',
        start: DateTime(2026, 10, 8, 9),
        end: DateTime(2026, 10, 8, 10),
      );
      await processor.apply(
        _request(AgendaRequestKind.delete, key: '9', series: true),
      );
      expect(phone.deleted, [('9', true)]);
    });

    test('background runs stop when not signed in', () async {
      final sync = AgendaPhoneSync(
        service: phone,
        client: SupabaseClient('http://localhost:1', 'test-key'),
        deviceId: 'device',
      );
      expect(await sync.background('calendar'), 'stop');
      expect(await processor.process(), 0);
    });
  });

  testWidgets('refused web changes are listed and can be dismissed', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _QueueService(db);
    await service.saveViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            today: const CivilDate(2026, 10, 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-failures')));
    await tester.pumpAndSettle();
    expect(find.text('Nuovo «Visita» · gio 8 ott 15:00'), findsOneWidget);
    expect(find.text('Calendario in sola lettura.'), findsOneWidget);
    await tester.tap(find.text('Ignora'));
    await tester.pumpAndSettle();
    expect(service.dismissed, ['r1']);
    expect(find.text('Nessuna.'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-failures')), findsNothing);
  });
}

class _FakePhone extends AgendaService {
  _FakePhone(super.database);

  final created = <AgendaEventDraft>[];
  final updated = <(String, AgendaEventDraft, bool)>[];
  final deleted = <(String, bool)>[];
  final existing = <String, AgendaEventDraft>{};

  @override
  Future<AgendaAccess> access() async => AgendaAccess.granted;

  @override
  Future<List<AgendaCalendar>> calendars() async => lastCalendars = const [
    AgendaCalendar(
      id: 'cal',
      name: 'Personale',
      accountName: 'me',
      writable: true,
    ),
    AgendaCalendar(id: 'shared', name: 'Team', accountName: 'work'),
  ];

  @override
  Future<AgendaEventDraft?> draftFor(String instanceId) async =>
      existing[instanceId];

  @override
  Future<String> createEvent(AgendaEventDraft draft) async {
    created.add(draft);
    return 'new';
  }

  @override
  Future<void> updateEvent(
    String instanceId,
    AgendaEventDraft draft, {
    bool series = false,
  }) async => updated.add((instanceId, draft, series));

  @override
  Future<void> deleteEvent(String instanceId, {bool series = false}) async =>
      deleted.add((instanceId, series));
}

class _QueueService extends AgendaService {
  _QueueService(super.database);

  final dismissed = <String>[];
  late List<AgendaRequest> _failed = [
    _request(
      AgendaRequestKind.create,
      status: AgendaRequestStatus.failed,
      error: 'Calendario in sola lettura.',
      payload: agendaRequestPayload(_timed, create: true),
    ),
  ];

  @override
  bool get writesViaPhone => true;

  @override
  bool get canOpenInSystem => false;

  @override
  List<AgendaRequest> get failedRequests => _failed;

  @override
  Future<void> dismissRequest(String id) async {
    dismissed.add(id);
    _failed = [
      for (final r in _failed)
        if (r.id != id) r,
    ];
  }

  @override
  Future<AgendaAccess> access() async => AgendaAccess.granted;

  @override
  Future<String?> deviceZoneLabel() async => 'Europe/London · UTC+1';

  @override
  Future<List<AgendaCalendar>> calendars() async => lastCalendars = const [
    AgendaCalendar(
      id: 'cal',
      name: 'Personale',
      accountName: 'me',
      writable: true,
    ),
  ];

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async => const [];
}
