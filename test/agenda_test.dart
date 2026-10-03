import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_day_view.dart';
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
    await service.saveViewMode(AgendaViewMode.list);
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
    expect(find.text('Calendari 3/3'), findsOneWidget);

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
    expect(find.text('Calendari 2/3'), findsOneWidget);
    expect(await service.calendarChoices(), {
      'kcl': true,
      'gmail': false,
      'slam': true,
    });
    expect(service.requestedCalendars.last, ['kcl', 'slam']);
  });

  testWidgets('la vista mese mostra la griglia e apre il giorno', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
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
      for (var hour = 8; hour < 13; hour++)
        event(
          'busy$hour',
          'kcl',
          'Clinica $hour',
          DateTime(2026, 10, 7, hour),
          DateTime(2026, 10, 7, hour, 30),
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
    expect(find.text('Ottobre 2026'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    final monday = find.byKey(const ValueKey('agenda-day-2026-10-05'));
    expect(
      find.descendant(of: monday, matching: find.text('Supervisione')),
      findsOneWidget,
    );
    // Five events, three slots: two chips and "+3".
    final busy = find.byKey(const ValueKey('agenda-day-2026-10-07'));
    expect(find.descendant(of: busy, matching: find.text('+3')), findsOne);
    expect(
      find.descendant(of: busy, matching: find.text('Clinica 8')),
      findsOne,
    );

    await tester.tap(monday);
    await tester.pumpAndSettle();
    expect(find.text('Lunedì 5 ottobre'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);
    expect(find.text('Partecipa · Teams'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Oggi · Lunedì 5 ottobre'), findsOneWidget);
    expect(await service.viewMode(), AgendaViewMode.list);
  });

  AgendaEntry entryAt(String id, int startHour, int startMinute, int minutes) {
    final start = DateTime(2026, 10, 5, startHour, startMinute);
    return AgendaEntry(
      instanceId: id,
      calendarIds: const ['kcl'],
      title: id,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      allDay: false,
    );
  }

  test('impagina la giornata in proporzione e affianca le sovrapposte', () {
    final blocks = layoutDayTimeline([
      entryAt('a', 9, 0, 60),
      entryAt('b', 9, 30, 60),
      entryAt('c', 10, 0, 30),
      entryAt('d', 14, 0, 0),
      AgendaEntry(
        instanceId: 'night',
        calendarIds: const ['kcl'],
        title: 'night',
        start: DateTime(2026, 10, 5, 23),
        end: DateTime(2026, 10, 6, 2),
        allDay: false,
      ),
      AgendaEntry(
        instanceId: 'allday',
        calendarIds: const ['kcl'],
        title: 'allday',
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 6),
        allDay: true,
      ),
    ], first);
    final byId = {for (final block in blocks) block.entry.instanceId: block};
    expect(byId.keys, ['a', 'b', 'c', 'd', 'night']);
    expect((byId['a']!.startMinute, byId['a']!.endMinute), (540, 600));
    // a and b overlap; c starts when a ends and reuses its column.
    expect(
      (byId['a']!.column, byId['b']!.column, byId['c']!.column),
      (0, 1, 0),
    );
    expect(byId['a']!.columns, 2);
    expect(byId['c']!.columns, 2);
    // Zero-length events still get a visible minimum height.
    expect((byId['d']!.startMinute, byId['d']!.endMinute), (840, 860));
    expect(byId['d']!.columns, 1);
    // Crossing midnight is clipped to the day.
    expect(
      (byId['night']!.startMinute, byId['night']!.endMinute),
      (1380, 1440),
    );
  });

  test('filtra inviti senza risposta e parole, senza maiuscole', () {
    final days = buildAgenda(
      events: [
        event(
          'b',
          'kcl',
          'All Staff Live Broadcast',
          DateTime(2026, 10, 5, 13, 30),
          DateTime(2026, 10, 5, 14),
        ),
        AgendaSourceEvent(
          instanceId: 't',
          calendarId: 'kcl',
          title: 'Tentative',
          start: DateTime(2026, 10, 5, 9),
          end: DateTime(2026, 10, 5, 10),
          allDay: false,
          unanswered: true,
        ),
        event(
          'r',
          'kcl',
          'Ward round',
          DateTime(2026, 10, 5, 11),
          DateTime(2026, 10, 5, 12),
        ),
      ],
      calendars: const [kcl],
      hiddenCalendarIds: const {},
      filter: const AgendaFilter(
        hideUnanswered: true,
        hiddenWords: ['live broadcast', '  '],
      ),
      first: first,
      days: 1,
    );
    expect(days.single.entries.map((entry) => entry.title), ['Ward round']);
    expect(const AgendaFilter(hiddenWords: ['x']).isActive, isTrue);
    expect(AgendaFilter.none.isActive, isFalse);
  });

  test('ricorda i filtri solo in locale', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = AgendaService(db);
    expect((await service.filter()).isActive, isFalse);
    await service.saveFilter(
      const AgendaFilter(hideUnanswered: true, hiddenWords: ['Live Broadcast']),
    );
    final restored = await AgendaService(db).filter();
    expect(restored.hideUnanswered, isTrue);
    expect(restored.hiddenWords, ['Live Broadcast']);
  });

  testWidgets('la vista giorno mostra i vuoti in proporzione', (tester) async {
    final created = <DateTime>[];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final days = [
      AgendaDay(first, [
        entryAt('early', 9, 0, 30),
        entryAt('late', 11, 0, 60),
      ]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AgendaDayPage(
          initialDay: first,
          today: first,
          loadDays: (_, _) async => days,
          peekDays: (_, _) => days,
          colors: const {},
          onOpen: (_) async {},
          onCreate: (start) async => created.add(start),
          now: () => DateTime(2026, 10, 5, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final early = tester.getTopLeft(
      find.byKey(const ValueKey('agenda-block-early')),
    );
    final late = tester.getTopLeft(
      find.byKey(const ValueKey('agenda-block-late')),
    );
    // Two hours apart on the clock: two hour-heights apart on screen.
    expect(late.dy - early.dy, closeTo(2 * AgendaDayPage.hourHeight, 0.5));
    final earlySize = tester.getSize(
      find.byKey(const ValueKey('agenda-block-early')),
    );
    expect(earlySize.height, closeTo(AgendaDayPage.hourHeight / 2 - 2, 0.5));

    // Free time between the meetings creates an event at that half hour.
    await tester.tapAt(
      early.translate(
        40,
        AgendaDayPage.hourHeight * 1.25, // 10:15 → slot 10:00
      ),
    );
    await tester.pumpAndSettle();
    expect(created, [DateTime(2026, 10, 5, 10)]);
  });

  test('sceglie il calendario per i nuovi eventi', () {
    const google = AgendaCalendar(
      id: 'g',
      name: 'me',
      accountName: 'me@gmail.com',
      writable: true,
      isGooglePrimary: true,
    );
    const outlook = AgendaCalendar(
      id: 'o',
      name: 'Calendario',
      accountName: 'k@kcl.ac.uk',
      writable: true,
    );
    const holidays = AgendaCalendar(
      id: 'h',
      name: 'Holidays',
      accountName: 'me@gmail.com',
    );
    expect(defaultEventCalendar([holidays, outlook, google], null), 'g');
    expect(defaultEventCalendar([holidays, outlook, google], 'o'), 'o');
    expect(defaultEventCalendar([holidays, outlook, google], 'h'), 'g');
    expect(defaultEventCalendar([holidays, outlook], null), 'o');
    expect(defaultEventCalendar([holidays], null), isNull);
    // Several Google accounts: the primary hidden in Agenda is skipped.
    const otherPrimary = AgendaCalendar(
      id: 'other',
      name: 'other',
      accountName: 'a@gmail.com',
      writable: true,
      isGooglePrimary: true,
    );
    expect(
      defaultEventCalendar(
        [otherPrimary, outlook, google],
        null,
        hidden: {'other'},
      ),
      'g',
    );
    expect(
      defaultEventCalendar(
        [otherPrimary, google],
        null,
        hidden: {'other', 'g'},
      ),
      'other',
    );
  });

  test('una bozza senza titolo o con fine prima dell inizio non si salva', () {
    final start = DateTime(2026, 10, 5, 9);
    AgendaEventDraft draft(String title, DateTime end) =>
        AgendaEventDraft(calendarId: 'g', title: title, start: start, end: end);
    expect(draft(' ', start.add(const Duration(hours: 1))).problem, isNotNull);
    expect(draft('Visita', start).problem, isNotNull);
    expect(
      draft('Visita', start.add(const Duration(hours: 1))).problem,
      isNull,
    );
  });

  testWidgets('il pulsante + crea un evento nel calendario Google', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, const [])..writableCalendars = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-new-event')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-event-save')));
    await tester.pumpAndSettle();
    expect(find.text('Inserisci un titolo.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agenda-event-title')),
      'Palestra',
    );
    await tester.tap(find.byKey(const ValueKey('agenda-event-save')));
    await tester.pumpAndSettle();
    final draft = service.createdDrafts.single;
    expect(draft.title, 'Palestra');
    expect(draft.calendarId, 'gmail');
    expect(draft.end.difference(draft.start), const Duration(hours: 1));
    expect(find.text('Evento salvato in Personale.'), findsOneWidget);
  });

  testWidgets('il filtro si imposta dal selettore calendari', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, [
      AgendaSourceEvent(
        instanceId: 'u',
        calendarId: 'kcl',
        title: 'Tentative',
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
        allDay: false,
        unanswered: true,
      ),
      event(
        'b',
        'kcl',
        'Live Broadcast: live from X',
        DateTime(2026, 10, 5, 13),
        DateTime(2026, 10, 5, 14),
      ),
      event(
        'k',
        'kcl',
        'Supervisione',
        DateTime(2026, 10, 5, 15),
        DateTime(2026, 10, 5, 16),
      ),
    ]);
    await service.saveViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tentative'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agenda-choose-calendars')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-hide-unanswered')));
    await tester.enterText(
      find.byKey(const ValueKey('agenda-hidden-word')),
      'live broadcast',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    expect(find.text('Tentative'), findsNothing);
    expect(find.text('Live Broadcast: live from X'), findsNothing);
    expect(find.text('Supervisione'), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    expect((await service.filter()).hiddenWords, ['live broadcast']);
  });

  test('legge le righe native senza descrizioni complete', () {
    final entry = agendaEventFromRow({
      'instanceId': '42@1759654800000',
      'calendarId': 'kcl',
      'title': 'Supervisione',
      'location': null,
      'links': 'https://teams.microsoft.com/l/meetup-join/abc',
      'start': DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
      'end': DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
      'allDay': false,
      'canceled': false,
    });
    expect(entry.start, DateTime(2026, 10, 5, 9));
    expect(findMeetingLink(entry)?.provider, 'Teams');
    expect(
      agendaEventFromRow({
        'instanceId': '1',
        'calendarId': 'kcl',
        'title': null,
        'start': 0,
        'end': 0,
      }).title,
      '',
    );
  });

  testWidgets('riaprendo mostra subito i dati e poi li aggiorna', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, [
      event(
        'k1',
        'kcl',
        'Supervisione',
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 10, 5, 10),
      ),
    ]);
    Widget app() => MaterialApp(
      home: Scaffold(
        body: AgendaView(service: service, today: first),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Supervisione'), findsOneWidget);

    // Leave Agenda, then come back while the provider is slow.
    await tester.pumpWidget(const SizedBox());
    service.gate = Completer<void>();
    await tester.pumpWidget(app());
    final readsBefore = service.requestedCalendars.length;
    await tester.pump();
    expect(find.text('Supervisione'), findsOneWidget);

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Supervisione'), findsOneWidget);
    // The visible months were read again in the background.
    expect(service.requestedCalendars.length, greaterThan(readsBefore));
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
    expect(find.text('Calendari 3/3'), findsOneWidget);
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

  bool writableCalendars = false;
  final createdDrafts = <AgendaEventDraft>[];

  @override
  Future<String> createEvent(AgendaEventDraft draft) async {
    createdDrafts.add(draft);
    return 'new';
  }

  /// When set, provider reads wait for it: simulates a slow provider.
  Completer<void>? gate;
  final _memory = <String, List<AgendaSourceEvent>>{};

  @override
  Future<List<AgendaCalendar>> calendars() async =>
      lastCalendars = writableCalendars
      ? const [
          kcl,
          AgendaCalendar(
            id: 'gmail',
            name: 'Personale',
            accountName: 'me@example.com',
            writable: true,
            isGooglePrimary: true,
          ),
          slam,
        ]
      : const [kcl, personal, slam];

  @override
  List<AgendaSourceEvent>? cachedEvents(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) => _memory['$start|$end|$calendarIds'];

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    requestedCalendars.add(calendarIds);
    await gate?.future;
    return _memory['$start|$end|$calendarIds'] = [
      for (final event in source)
        if (calendarIds.contains(event.calendarId) &&
            event.start.isBefore(end) &&
            event.end.isAfter(start))
          event,
    ];
  }
}
