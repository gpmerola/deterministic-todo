import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const kcl = AgendaCalendar(
  id: 'kcl',
  name: 'Calendar',
  accountName: 'kcl@example.ac.uk',
  colorHex: '#0078D4',
);
const slam = AgendaCalendar(
  id: 'slam',
  name: 'Calendar',
  accountName: 'slam@example.nhs.uk',
);
const personal = AgendaCalendar(
  id: 'gmail',
  name: 'Personale',
  accountName: 'me@example.com',
);

AgendaSourceEvent event(
  String id,
  String calendar,
  String title,
  DateTime start,
  DateTime end, {
  bool allDay = false,
  bool canceled = false,
  String? description,
  String? location,
}) => AgendaSourceEvent(
  instanceId: id,
  calendarId: calendar,
  title: title,
  start: start,
  end: end,
  allDay: allDay,
  canceled: canceled,
  description: description,
  location: location,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  const first = CivilDate(2026, 10, 5);

  test('mostra una sola volta la stessa riunione su due account', () {
    final days = buildAgenda(
      events: [
        event(
          's1',
          'slam',
          'Ward round',
          DateTime(2026, 10, 5, 9),
          DateTime(2026, 10, 5, 10),
        ),
        event(
          'k1',
          'kcl',
          'ward round ',
          DateTime(2026, 10, 5, 9),
          DateTime(2026, 10, 5, 10),
          description:
              'Join: <https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=1>',
        ),
      ],
      calendars: const [kcl, slam],
      hiddenCalendarIds: const {},
      first: first,
      days: 1,
    );
    final entries = days.single.entries;
    expect(entries, hasLength(1));
    expect(entries.single.calendarIds, ['kcl', 'slam']);
    expect(entries.single.meeting?.provider, 'Teams');
    expect(
      entries.single.meeting?.url.toString(),
      'https://teams.microsoft.com/l/meetup-join/19%3Ameeting_x/0?context=1',
    );
  });

  test('esclude calendari nascosti, sconosciuti ed eventi annullati', () {
    final days = buildAgenda(
      events: [
        event(
          'a',
          'gmail',
          'Palestra',
          DateTime(2026, 10, 5, 18),
          DateTime(2026, 10, 5, 19),
        ),
        event(
          'b',
          'kcl',
          'Annullata',
          DateTime(2026, 10, 5, 11),
          DateTime(2026, 10, 5, 12),
          canceled: true,
        ),
        event(
          'c',
          'other',
          'Fuori elenco',
          DateTime(2026, 10, 5, 8),
          DateTime(2026, 10, 5, 9),
        ),
        event(
          'd',
          'kcl',
          'Seminario',
          DateTime(2026, 10, 5, 14),
          DateTime(2026, 10, 5, 15),
        ),
      ],
      calendars: const [kcl, personal],
      hiddenCalendarIds: const {'gmail'},
      first: first,
      days: 1,
    );
    expect(days.single.entries.map((entry) => entry.title), ['Seminario']);
  });

  test('ordina e distribuisce eventi su più giorni', () {
    final days = buildAgenda(
      events: [
        event(
          'late',
          'kcl',
          'Notte',
          DateTime(2026, 10, 5, 22),
          DateTime(2026, 10, 6, 2),
        ),
        event(
          'conf',
          'kcl',
          'Congresso',
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 7),
          allDay: true,
        ),
        event(
          'early',
          'kcl',
          'Presto',
          DateTime(2026, 10, 5, 8),
          DateTime(2026, 10, 5, 8),
        ),
      ],
      calendars: const [kcl],
      hiddenCalendarIds: const {},
      first: first,
      days: 3,
    );
    expect(days.map((day) => day.date.toString()), [
      '2026-10-05',
      '2026-10-06',
      '2026-10-07',
    ]);
    expect(days[0].entries.map((entry) => entry.title), [
      'Congresso',
      'Presto',
      'Notte',
    ]);
    expect(days[1].entries.map((entry) => entry.title), ['Congresso', 'Notte']);
    expect(days[2].entries, isEmpty);

    final late = days[0].entries.last;
    expect(agendaTimeLabel(late, first), 'dalle 22:00');
    expect(agendaTimeLabel(late, first.addDays(1)), 'fino 02:00');
    expect(agendaTimeLabel(days[0].entries[1], first), '08:00');
    expect(agendaTimeLabel(days[0].entries.first, first), 'Tutto il giorno');
  });

  test('non ripete i nomi dei calendari di provenienza', () {
    expect(
      agendaCalendarLabel(['Holidays in Italy', 'Holidays in Italy']),
      'Holidays in Italy',
    );
    expect(
      agendaCalendarLabel(['Calendario', '', 'Calendar']),
      'Calendario · Calendar',
    );
  });

  test('riconosce Zoom e Meet e ignora testo senza link', () {
    MeetingLink? link(String text) => findMeetingLink(
      event('x', 'kcl', 't', DateTime(2026), DateTime(2026), location: text),
    );
    expect(link('https://kcl.zoom.us/j/123?pwd=a.')?.provider, 'Zoom');
    expect(
      link('https://kcl.zoom.us/j/123?pwd=a.')?.url.toString(),
      'https://kcl.zoom.us/j/123?pwd=a',
    );
    expect(link('https://meet.google.com/abc-defg-hij')?.provider, 'Meet');
    expect(link('Riunione di Microsoft Teams'), isNull);
  });

  test('i calendari nascosti dal telefono restano attivabili', () {
    const systemHidden = AgendaCalendar(
      id: 'unifi',
      name: 'unifi',
      accountName: 'me@example.it',
      visibleBySystem: false,
    );
    const calendars = [kcl, systemHidden];
    expect(hiddenAgendaCalendars(calendars, const {}), {'unifi'});
    expect(
      hiddenAgendaCalendars(calendars, const {'unifi': true, 'kcl': false}),
      {'kcl'},
    );
  });

  test('ricorda le scelte dei calendari solo in locale', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = AgendaService(db);
    expect(await service.calendarChoices(), isEmpty);
    await service.saveCalendarChoices({'slam': false, 'unifi': true});
    expect(await service.calendarChoices(), {'slam': false, 'unifi': true});
  });

  test('legge come nascosti i calendari scelti con la build 191', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AgendaService.legacyHiddenCalendarsKey,
            value: '["gmail"]',
          ),
        );
    final service = AgendaService(db);
    expect(await service.calendarChoices(), {'gmail': false});
    await service.saveCalendarChoices({'gmail': true});
    expect(await service.calendarChoices(), {'gmail': true});
  });

  testWidgets('mostra gli eventi uniti e filtra i calendari', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, [
      event(
        'k1',
        'kcl',
        'Supervisione',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 5, 10),
        description: 'https://teams.microsoft.com/l/meetup-join/abc',
      ),
      event(
        'g1',
        'gmail',
        'Cena',
        DateTime(2026, 10, 6, 20),
        DateTime(2026, 10, 6, 22),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Oggi · Lunedì 5 ottobre'), findsOneWidget);
    expect(find.text('Supervisione'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);
    expect(find.text('Teams'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    expect(find.text('3 di 3 calendari'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agenda-choose-calendars')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SwitchListTile),
        matching: find.text('Personale'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();
    expect(find.text('Cena'), findsNothing);
    expect(find.text('2 di 3 calendari'), findsOneWidget);
    expect(await service.calendarChoices(), {
      'kcl': true,
      'gmail': false,
      'slam': true,
    });
    expect(service.requestedCalendars.last, ['kcl', 'slam']);
  });

  testWidgets('chiede il permesso senza leggere calendari', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, const [])
      ..currentAccess = AgendaAccess.askable;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Consenti accesso al calendario'), findsOneWidget);
    expect(service.requestedCalendars, isEmpty);

    await tester.tap(find.text('Consenti accesso al calendario'));
    await tester.pumpAndSettle();
    expect(find.text('3 di 3 calendari'), findsOneWidget);
  });
}

class _FakeAgendaService extends AgendaService {
  _FakeAgendaService(super.database, this.source);

  final List<AgendaSourceEvent> source;
  final requestedCalendars = <List<String>>[];
  AgendaAccess currentAccess = AgendaAccess.granted;

  @override
  Future<AgendaAccess> access() async => currentAccess;

  @override
  Future<AgendaAccess> requestAccess() async =>
      currentAccess = AgendaAccess.granted;

  @override
  Future<List<AgendaCalendar>> calendars() async => const [kcl, personal, slam];

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    requestedCalendars.add(calendarIds);
    return [
      for (final event in source)
        if (calendarIds.contains(event.calendarId) &&
            event.start.isBefore(end) &&
            event.end.isAfter(start))
          event,
    ];
  }
}
