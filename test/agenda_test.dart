import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/agenda_tasks.dart';
import 'package:deterministic_todo/ui/search.dart';
import 'package:deterministic_todo/ui/views/agenda_day_view.dart';
import 'package:deterministic_todo/ui/views/agenda_event_editor.dart';
import 'package:deterministic_todo/ui/views/agenda_month_view.dart';
import 'package:deterministic_todo/ui/views/agenda_view.dart';
import 'package:deterministic_todo/ui/views/agenda_week_view.dart';
import 'package:deterministic_todo/ui/views/today_agenda_strip.dart';
import 'package:drift/drift.dart' show Value;
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

final picked = <String?>[];

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
    expect(find.text('3/3'), findsOneWidget);

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
    expect(find.text('2/3'), findsOneWidget);
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
      for (var hour = 7; hour < 22; hour++)
        event(
          'busy$hour',
          'kcl',
          'Clinica $hour',
          DateTime(2026, 10, 7, hour),
          DateTime(2026, 10, 7, hour, 30),
        ),
    ]);
    await service.saveViewMode(AgendaViewMode.month);
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
      find.descendant(of: monday, matching: find.text('9 Supervisione')),
      findsOneWidget,
    );
    // The month fills the screen: a day shows every entry that fits its
    // height, then "+N" for the rest.
    final busy = find.byKey(const ValueKey('agenda-day-2026-10-07'));
    expect(
      find.descendant(of: busy, matching: find.text('7 Clinica 7')),
      findsOne,
    );
    final shown = tester
        .widgetList(
          find.descendant(of: busy, matching: find.byType(AgendaChip)),
        )
        .length;
    expect(shown, greaterThan(3));
    expect(
      find.descendant(of: busy, matching: find.text('+${15 - shown}')),
      findsOne,
    );
    // Neighbouring months complete the weeks of October.
    expect(find.byKey(const ValueKey('agenda-day-2026-09-28')), findsOne);
    expect(find.byKey(const ValueKey('agenda-day-2026-11-01')), findsOne);

    await tester.tap(monday);
    await tester.pumpAndSettle();
    expect(find.text('Lunedì 5 ottobre'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);
    expect(find.text('Partecipa · Teams'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('agenda-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-mode-list')));
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

  test('il calendario dell assistente si sceglie e si azzera', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = AgendaService(db);
    expect(await service.aiEventCalendar(), isNull);
    await service.saveAiEventCalendar('ai-cal');
    expect(await service.aiEventCalendar(), 'ai-cal');
    await service.saveAiEventCalendar(null);
    expect(await service.aiEventCalendar(), isNull);
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

  test(
    'le attività segnate compaiono come giornata intera, serie compresa',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TaskRepository(db, deviceId: 'synthetic-device');
      final links = AgendaTaskLinks(db);
      final single = await repo.create(
        'Rinnovo passaporto',
        showDate: '2026-10-06',
      );
      final other = await repo.create('Non in agenda', showDate: '2026-10-06');
      final gone = await repo.create('Cancellata', showDate: '2026-10-07');
      Future<Task> load(String id) =>
          (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
      await links.setShown(await load(single), true);
      await links.setShown(await load(gone), true);
      await repo.softDelete(await load(gone));
      // A recurring series is flagged once for every occurrence.
      await db
          .into(db.tasks)
          .insert(
            (await load(other)).copyWith(
              id: 'occ-1',
              title: 'Terapia',
              seriesId: const Value('series-a'),
              showDate: const Value('2026-10-08'),
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            (await load(other)).copyWith(
              id: 'occ-2',
              title: 'Terapia',
              seriesId: const Value('series-a'),
              showDate: const Value('2026-10-15'),
            ),
          );
      await links.setShown(await load('occ-1'), true);
      expect(await links.isShown(await load('occ-2')), isTrue);
      expect(await links.isShown(await load(other)), isFalse);

      final tasks = await links.tasksBetween(first, 14);
      expect([for (final t in tasks) '${t.date} ${t.title}']..sort(), [
        '2026-10-06 Rinnovo passaporto',
        '2026-10-08 Terapia',
        '2026-10-15 Terapia',
      ]);
      final day = buildAgenda(
        events: [
          event(
            'e',
            'kcl',
            'Clinica',
            DateTime(2026, 10, 6, 9),
            DateTime(2026, 10, 6, 10),
          ),
        ],
        tasks: tasks,
        calendars: const [kcl],
        hiddenCalendarIds: const {},
        first: first.addDays(1),
        days: 1,
      ).single;
      expect(day.entries.map((e) => e.title), [
        'Rinnovo passaporto',
        'Clinica',
      ]);
      expect(day.entries.first.isTask, isTrue);
      expect(day.entries.first.allDay, isTrue);

      await links.setShown(await load(single), false);
      expect(await links.tasksBetween(first.addDays(1), 1), isEmpty);
    },
  );

  test('traduce la ripetizione in regola RRULE con fine inclusiva', () {
    AgendaEventDraft draft(AgendaRepeat repeat, {CivilDate? until}) =>
        AgendaEventDraft(
          calendarId: 'g',
          title: 'Corso',
          start: DateTime(2026, 10, 5, 9),
          end: DateTime(2026, 10, 5, 10),
          repeat: repeat,
          repeatUntil: until,
        );
    expect(AgendaService.recurrenceRuleFor(draft(AgendaRepeat.none)), isNull);
    expect(
      AgendaService.recurrenceRuleFor(
        draft(AgendaRepeat.daily),
      )!.toRruleString(),
      'FREQ=DAILY',
    );
    final weekdays = AgendaService.recurrenceRuleFor(
      draft(AgendaRepeat.weekdays, until: const CivilDate(2026, 12, 18)),
    )!.toRruleString();
    expect(weekdays, contains('FREQ=WEEKLY'));
    expect(weekdays, contains('BYDAY=MO,TU,WE,TH,FR'));
    expect(weekdays, contains('UNTIL='));
    expect(
      agendaRepeatLabel(AgendaRepeat.weekly, DateTime(2026, 10, 5)),
      'Ogni settimana di lunedì',
    );
    expect(
      agendaRepeatLabel(AgendaRepeat.yearly, DateTime(2026, 10, 5)),
      'Ogni anno il 5 ottobre',
    );
    expect(
      draft(AgendaRepeat.daily, until: const CivilDate(2026, 10, 1)).problem,
      isNotNull,
    );
  });

  testWidgets('il modulo crea un evento ricorrente', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    AgendaEventDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<AgendaEventDraft>(
                MaterialPageRoute(
                  builder: (_) => AgendaEventEditor(
                    calendars: const [
                      AgendaCalendar(
                        id: 'g',
                        name: 'Personale',
                        accountName: 'me@example.com',
                        writable: true,
                      ),
                    ],
                    initialStart: DateTime(2026, 10, 5, 9),
                    zoneLabel: 'Europe/London · UTC+1',
                  ),
                ),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agenda-event-title')),
      'Corso',
    );
    await tester.tap(find.byKey(const ValueKey('agenda-event-repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ogni settimana di lunedì').last);
    await tester.pumpAndSettle();
    expect(find.text('Senza fine'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-event-save')));
    await tester.pumpAndSettle();
    expect(result?.repeat, AgendaRepeat.weekly);
    expect(result?.repeatUntil, isNull);
  });

  testWidgets('la vista settimana mette le ore in scala per colonna', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final created = <DateTime>[];
    final days = buildAgenda(
      events: [
        event(
          'a',
          'kcl',
          'A',
          DateTime(2026, 10, 6, 9),
          DateTime(2026, 10, 6, 10),
        ),
        event(
          'b',
          'kcl',
          'B',
          DateTime(2026, 10, 6, 11),
          DateTime(2026, 10, 6, 12),
        ),
      ],
      calendars: const [kcl],
      hiddenCalendarIds: const {},
      first: first,
      days: 7,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaWeekView(
            today: first,
            revision: 0,
            loadDays: (_, _) async => days,
            peekDays: (_, _) => days,
            colors: const {},
            onOpenDay: (_) {},
            onOpen: (_) async {},
            onCreate: (start) async => created.add(start),
            now: () => DateTime(2026, 10, 5, 8),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 – 11 ottobre 2026'), findsOneWidget);
    final a = tester.getTopLeft(
      find.byKey(const ValueKey('agenda-week-block-a')),
    );
    final b = tester.getTopLeft(
      find.byKey(const ValueKey('agenda-week-block-b')),
    );
    expect(b.dy - a.dy, closeTo(2 * AgendaWeekView.hourHeight, 0.5));
    expect(b.dx, a.dx);
    // Tuesday 10:15 is free: creates at 10:00 on that column.
    await tester.tapAt(a.translate(10, AgendaWeekView.hourHeight * 1.25));
    await tester.pumpAndSettle();
    expect(created, [DateTime(2026, 10, 6, 10)]);
  });

  test('la ricerca mette prima i prossimi, poi i passati più recenti', () {
    AgendaEntry at(String id, DateTime start) => AgendaEntry(
      instanceId: id,
      calendarIds: const ['kcl'],
      title: id,
      start: start,
      end: start.add(const Duration(hours: 1)),
      allDay: false,
    );
    final now = DateTime(2026, 10, 5, 12);
    final ordered = orderSearchResults(
      [
        at('old', DateTime(2026, 1, 1, 9)),
        at('later', DateTime(2026, 12, 1, 9)),
        at('recent', DateTime(2026, 10, 1, 9)),
        at('soon', DateTime(2026, 10, 6, 9)),
      ],
      now,
      limit: 3,
    );
    expect(ordered.map((e) => e.instanceId), ['soon', 'later', 'recent']);
  });

  testWidgets('la ricerca mostra anche gli eventi', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepository(db, deviceId: 'synthetic-device');
    final opened = <String>[];
    final queries = <String>[];
    final delegate = TaskSearchDelegate(
      repo,
      onNavigate: (_) {},
      onCreate: (_) async {},
      tileBuilder: (task) => ListTile(title: Text(task.title)),
      searchEvents: (text) async {
        queries.add(text);
        return [
          AgendaEntry(
            instanceId: '5',
            calendarIds: const ['kcl'],
            title: 'Ward round',
            start: DateTime(2026, 10, 6, 9),
            end: DateTime(2026, 10, 6, 10),
            allDay: false,
          ),
        ];
      },
      openEvent: (_, entry) async => opened.add(entry.instanceId),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showSearch<void>(context: context, delegate: delegate),
            child: const Text('cerca'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('cerca'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ward');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-events-header')), findsOneWidget);
    expect(find.text('Ward round'), findsOneWidget);
    await tester.tap(find.text('Ward round'));
    await tester.pumpAndSettle();
    expect(opened, ['5']);
    expect(queries, ['ward']);
    // Let Drift's stream timers settle before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('si sceglie il calendario dei nuovi eventi', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showModalBottomSheet<AgendaPickerResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AgendaCalendarPicker(
                  calendars: [
                    AgendaCalendar(
                      id: 'op',
                      name: 'op',
                      accountName: 'op',
                      writable: true,
                      isGooglePrimary: true,
                    ),
                    AgendaCalendar(
                      id: 'me',
                      name: 'Personale',
                      accountName: 'me@example.com',
                      writable: true,
                      isGooglePrimary: true,
                    ),
                  ],
                  hidden: {},
                  eventCalendarId: 'op',
                ),
              );
              picked
                ..add(result?.eventCalendarId)
                ..add(result?.aiEventCalendarId);
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('agenda-event-calendar-default')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personale · me@example.com').last);
    await tester.pumpAndSettle();
    // A separate calendar for ✨ events, distinct from the + one.
    await tester.tap(find.byKey(const ValueKey('agenda-ai-event-calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('op').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();
    expect(picked, ['me', 'op']);
  });

  test('fuso e nomi brevi per l intestazione e le proposte', () {
    expect(shortZoneLabel('Europe/London · UTC+1'), 'London · UTC+1');
    expect(
      shortZoneLabel('America/Argentina/Buenos_Aires · UTC−3'),
      'Buenos Aires · UTC−3',
    );
    expect(shortCalendarName('sennar.pierp@gmail.com'), 'sennar.pierp');
    expect(shortCalendarName('✨ Assistente'), '✨ Assistente');
  });

  test('attività collegate: giorno lavorativo prima e dopo', () {
    // Monday meeting: prepare on Friday; follow up on Tuesday.
    final monday = AgendaEntry(
      instanceId: 'm',
      calendarIds: const ['kcl'],
      title: 'TNG Meeting',
      start: DateTime(2026, 10, 12, 11),
      end: DateTime(2026, 10, 12, 12),
      allDay: false,
    );
    final prep = linkedTaskFor(
      monday,
      followUp: false,
      eventLabel: 'TNG · lun',
    );
    expect(prep.title, 'Preparare: TNG Meeting');
    expect(prep.date, const CivilDate(2026, 10, 9));
    expect(prep.notes, 'Collegata a: TNG · lun');
    expect(
      linkedTaskFor(monday, followUp: true, eventLabel: '').date,
      const CivilDate(2026, 10, 13),
    );
    // All-day Thu–Fri congress: follow-up on the next Monday.
    final congress = AgendaEntry(
      instanceId: 'c',
      calendarIds: const ['kcl'],
      title: 'Congresso',
      start: DateTime(2026, 11, 12),
      end: DateTime(2026, 11, 14),
      allDay: true,
    );
    expect(
      linkedTaskFor(congress, followUp: true, eventLabel: '').date,
      const CivilDate(2026, 11, 16),
    );
  });

  testWidgets('Preparare dal dettaglio crea l attività collegata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, [
      event(
        'k',
        'kcl',
        'TNG Meeting',
        DateTime(2026, 10, 8, 15, 30),
        DateTime(2026, 10, 8, 16, 30),
      ),
    ]);
    await service.saveViewMode(AgendaViewMode.list);
    final created = <(String, CivilDate, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            today: first,
            onCreateTask: (title, date, notes) async =>
                created.add((title, date, notes)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TNG Meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-sheet-prepare')));
    await tester.pumpAndSettle();
    expect(created.single.$1, 'Preparare: TNG Meeting');
    expect(created.single.$2, const CivilDate(2026, 10, 7));
    expect(created.single.$3, 'Collegata a: TNG Meeting · gio 8 ott 15:30');
  });

  testWidgets('la striscia di Oggi mostra solo gli impegni che restano', (
    tester,
  ) async {
    final entries = [
      AgendaEntry(
        instanceId: 'past',
        calendarIds: const ['kcl'],
        title: 'Già fatta',
        start: DateTime(2026, 10, 5, 8),
        end: DateTime(2026, 10, 5, 9),
        allDay: false,
      ),
      AgendaEntry(
        instanceId: 'next',
        calendarIds: const ['kcl'],
        title: 'TNG',
        start: DateTime(2026, 10, 5, 11),
        end: DateTime(2026, 10, 5, 12),
        allDay: false,
      ),
      AgendaEntry(
        instanceId: 'holiday',
        calendarIds: const ['kcl'],
        title: 'Festa',
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 6),
        allDay: true,
      ),
      AgendaEntry(
        instanceId: 'task:x',
        calendarIds: const [AgendaEntry.tasksCalendarId],
        title: 'Attività',
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 6),
        allDay: true,
        taskId: 'x',
      ),
    ];
    var opened = 0;
    Future<void> pump(List<AgendaEntry> list) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayAgendaStrip(
            key: UniqueKey(),
            dayKey: '2026-10-05',
            loadEntries: () async => list,
            onOpen: () => opened++,
            now: () => DateTime(2026, 10, 5, 10),
          ),
        ),
      ),
    );
    await pump(entries);
    await tester.pumpAndSettle();
    expect(find.text('11:00 TNG · 1 tutto il giorno'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('today-agenda-strip')));
    expect(opened, 1);
    await pump(const []);
    await tester.pumpAndSettle();
    expect(find.text('Nessun altro impegno oggi'), findsOneWidget);
  });

  test('orario compatto nelle celle', () {
    expect(compactTime(DateTime(2026, 10, 5, 9)), '9');
    expect(compactTime(DateTime(2026, 10, 5, 16, 30)), '16:30');
    expect(compactTime(DateTime(2026, 10, 5, 8, 5)), '8:05');
  });

  testWidgets('senza barra superiore cerca e impostazioni restano nel menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, const []);
    var searched = 0;
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(
            service: service,
            today: first,
            onSearch: () => searched++,
            onSettings: () => settings++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Zone, mode, today and calendars share one row above the days.
    final zone = tester.getTopLeft(find.byKey(const ValueKey('agenda-zone')));
    final mode = tester.getTopLeft(find.byKey(const ValueKey('agenda-mode')));
    expect((zone.dy - mode.dy).abs(), lessThan(24));
    await tester.tap(find.byKey(const ValueKey('agenda-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect((searched, settings), (1, 1));
  });

  test('mostra il fuso sempre come IANA con lo scarto da UTC', () {
    expect(zoneLabel('Europe/London', 3600), 'Europe/London · UTC+1');
    expect(zoneLabel('Europe/London', 0), 'Europe/London · UTC');
    expect(zoneLabel('Asia/Kolkata', 19800), 'Asia/Kolkata · UTC+5:30');
    expect(zoneLabel('America/New_York', -14400), 'America/New_York · UTC−4');
  });

  testWidgets('il mese è predefinito; la vista a 2 settimane mostra il fuso', (
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
      event(
        'k2',
        'kcl',
        'Ward round',
        DateTime(2026, 10, 16, 8, 30),
        DateTime(2026, 10, 16, 9),
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
    expect(await service.viewMode(), AgendaViewMode.month);
    expect(find.text('Ottobre 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-mode-twoWeeks')));
    await tester.pumpAndSettle();
    expect(find.text('5 – 18 ottobre 2026'), findsOneWidget);
    expect(find.text('London · UTC+1'), findsOneWidget);
    expect(find.text('9 Supervisione'), findsOneWidget);
    expect(find.text('8:30 Ward round'), findsOneWidget);
    expect(await service.viewMode(), AgendaViewMode.twoWeeks);

    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-10-05')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agenda-day-zone'))).data,
      'Europe/London · UTC+1',
    );
  });

  Future<_FakeAgendaService> listWith(
    WidgetTester tester,
    List<AgendaSourceEvent> events,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeAgendaService(db, events)..writableCalendars = true;
    await service.saveViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('modifica un evento dal dettaglio', (tester) async {
    final service = await listWith(tester, [
      AgendaSourceEvent(
        instanceId: '7',
        calendarId: 'gmail',
        title: 'Palestra',
        start: DateTime(2026, 10, 5, 18),
        end: DateTime(2026, 10, 5, 19),
        allDay: false,
        timeZone: 'Europe/Rome',
        eventZoneTimes: '19:00–20:00',
      ),
    ]);
    await tester.tap(find.text('Palestra'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Orario originale 19:00–20:00 Europe/Rome'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('agenda-sheet-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Modifica evento'), findsOneWidget);
    expect(find.text('Note complete'), findsOneWidget);
    expect(find.text('Fuso orario: Europe/London · UTC+1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('agenda-event-title')),
      'Palestra con Luca',
    );
    await tester.tap(find.byKey(const ValueKey('agenda-event-save')));
    await tester.pumpAndSettle();
    final (id, draft, series) = service.updates.single;
    expect((id, series), ('7', false));
    expect(draft.title, 'Palestra con Luca');
    expect(draft.start, DateTime(2026, 10, 5, 18));
    expect(draft.end, DateTime(2026, 10, 5, 19));
    expect(find.text('Evento aggiornato.'), findsOneWidget);
  });

  testWidgets('elimina una serie solo dopo la scelta esplicita', (
    tester,
  ) async {
    final service = await listWith(tester, [
      AgendaSourceEvent(
        instanceId: '9@1759654800000',
        calendarId: 'gmail',
        title: 'Corso',
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
        allDay: false,
      ),
      AgendaSourceEvent(
        instanceId: '10',
        calendarId: 'gmail',
        title: 'Cena',
        start: DateTime(2026, 10, 5, 20),
        end: DateTime(2026, 10, 5, 21),
        allDay: false,
      ),
    ]);
    await tester.tap(find.text('Corso'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-sheet-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-scope-series')));
    await tester.pumpAndSettle();
    expect(service.deletions, [('9@1759654800000', true)]);

    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-sheet-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(service.deletions, hasLength(1));
  });

  testWidgets('gli inviti altrui non si modificano', (tester) async {
    await listWith(tester, [
      AgendaSourceEvent(
        instanceId: '11',
        calendarId: 'gmail',
        title: 'Riunione esterna',
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
        allDay: false,
        isOrganizer: false,
      ),
    ]);
    await tester.tap(find.text('Riunione esterna'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-sheet-edit')), findsNothing);
    expect(find.byKey(const ValueKey('agenda-sheet-delete')), findsNothing);
    expect(find.textContaining('Invito di un altro organizzatore'), findsOne);
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
      'timeZone': 'Europe/Rome',
      'eventZoneTimes': '10:00–11:00',
      'organizer': false,
    });
    expect(entry.start, DateTime(2026, 10, 5, 9));
    expect(entry.timeZone, 'Europe/Rome');
    expect(entry.eventZoneTimes, '10:00–11:00');
    expect(entry.isOrganizer, isFalse);
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
    expect(find.textContaining('Supervisione'), findsOneWidget);

    // Leave Agenda, then come back while the provider is slow.
    await tester.pumpWidget(const SizedBox());
    service.gate = Completer<void>();
    await tester.pumpWidget(app());
    final readsBefore = service.requestedCalendars.length;
    await tester.pump();
    expect(find.textContaining('Supervisione'), findsOneWidget);

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Supervisione'), findsOneWidget);
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
    expect(find.text('3/3'), findsOneWidget);
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
  Future<String?> deviceZoneLabel() async =>
      lastZoneLabel = 'Europe/London · UTC+1';

  @override
  Future<AgendaAccess> requestAccess() async =>
      currentAccess = AgendaAccess.granted;

  bool writableCalendars = false;
  final createdDrafts = <AgendaEventDraft>[];
  final updates = <(String, AgendaEventDraft, bool)>[];
  final deletions = <(String, bool)>[];

  @override
  Future<AgendaEventDraft?> draftFor(String instanceId) async {
    final event = source.firstWhere((e) => e.instanceId == instanceId);
    return AgendaEventDraft(
      calendarId: event.calendarId,
      title: event.title,
      start: event.start,
      end: event.end,
      allDay: event.allDay,
      location: event.location,
      notes: 'Note complete',
    );
  }

  @override
  Future<void> updateEvent(
    String instanceId,
    AgendaEventDraft draft, {
    bool series = false,
  }) async => updates.add((instanceId, draft, series));

  @override
  Future<void> deleteEvent(String instanceId, {bool series = false}) async =>
      deletions.add((instanceId, series));

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
