import 'dart:convert';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/semble_bookings.dart';
import 'package:deterministic_todo/domain/semble_ical.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:deterministic_todo/ui/semble_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

// Synthetic feed and rules; the link, ids and visits are made up.
const link = 'webcal://example.test/ical/feed-token.ics';
const thu29 = CivilDate(2026, 10, 29);

String feed(List<String> events) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//Test//Semble//EN',
  ...events,
  'END:VCALENDAR',
].join('\r\n');

String event(
  String start, {
  String? end,
  String summary = "Follow-up 30'",
  String extra = '',
}) => [
  'BEGIN:VEVENT',
  'UID:${start.hashCode}@test',
  'DTSTART$start',
  if (end != null) 'DTEND$end',
  'SUMMARY:$summary',
  if (extra.isNotEmpty) extra,
  'END:VEVENT',
].join('\r\n');

Map<String, Object?> rule() => {
  'id': 'r1',
  'unavailability': false,
  'startDate': '2026-01-05',
  'endDate': null,
  'startTime': '10:00',
  'endTime': '18:00',
  'exclusions': const [],
  'recurrence': {
    'frequency': 'weekly',
    'interval': 1,
    'daysOfTheWeek': [4],
  },
};

http.Response rulesResponse() => http.Response(
  jsonEncode({
    'data': {
      'availabilityRules': {
        'data': [rule()],
      },
    },
  }),
  200,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  final from = DateTime.utc(2026, 10, 1);
  final to = DateTime.utc(2026, 12, 1);

  group('feed iCal', () {
    test('link https o webcal, mai in chiaro', () {
      expect(
        sembleIcalUri(' webcal://example.test/a.ics ').toString(),
        'https://example.test/a.ics',
      );
      expect(sembleIcalUri('https://example.test/a.ics'), isNotNull);
      expect(sembleIcalUri('http://example.test/a.ics'), isNull);
      expect(sembleIcalUri('feed'), isNull);
      expect(sembleIcalUri(''), isNull);
    });

    test('orari UTC, ora di Londra, righe piegate e annullate', () {
      final bookings = parseSembleIcal(
        feed([
          // Instant in UTC.
          event(':20261030T101500Z', end: ':20261030T104500Z'),
          // London wall clock in BST: 10:00 London is 09:00 UTC.
          event(
            ';TZID=Europe/London:20261022T100000',
            end: ';TZID=Europe/London:20261022T101500',
            summary: 'Prima visita\r\n  (adulto)',
          ),
          event(
            ':20261103T090000Z',
            end: ':20261103T093000Z',
            extra: 'STATUS:CANCELLED',
          ),
          // All day: not a visit.
          event(';VALUE=DATE:20261104', end: ';VALUE=DATE:20261105'),
          // Outside the window.
          event(':20270105T090000Z', end: ':20270105T093000Z'),
        ]),
        from: from,
        to: to,
      );
      expect(bookings, hasLength(3));
      expect(bookings[0].start.toUtc(), DateTime.utc(2026, 10, 22, 9));
      expect(bookings[0].end!.toUtc(), DateTime.utc(2026, 10, 22, 9, 15));
      expect(bookings[0].appointmentTitle, 'Prima visita (adulto)');
      expect(bookings[1].start.toUtc(), DateTime.utc(2026, 10, 30, 10, 15));
      expect(bookings[1].deleted, isFalse);
      expect(bookings[2].deleted, isTrue);
    });

    test('senza fine: DURATION, poi i minuti del titolo, poi 15', () {
      final bookings = parseSembleIcal(
        feed([
          event(':20261030T090000Z', extra: 'DURATION:PT45M'),
          event(':20261030T100000Z', summary: 'Follow-up (20 min)'),
          event(':20261030T110000Z', summary: 'Visita'),
        ]),
        from: from,
        to: to,
      );
      expect(
        [for (final b in bookings) b.end!.difference(b.start)],
        const [
          Duration(minutes: 45),
          Duration(minutes: 20),
          Duration(minutes: 15),
        ],
      );
    });

    test(
      'il client legge il link senza chiave e riconosce i rifiuti',
      () async {
        Uri? asked;
        Map<String, String>? headers;
        final client = SembleIcalClient(
          client: MockClient((request) async {
            asked = request.url;
            headers = request.headers;
            return http.Response(
              feed([event(':20261030T090000Z', end: ':20261030T093000Z')]),
              200,
            );
          }),
        );
        final bookings = await client.bookings(link: link, from: from, to: to);
        expect(bookings, hasLength(1));
        expect(asked.toString(), 'https://example.test/ical/feed-token.ics');
        expect(
          headers!.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-token')),
        );

        Future<SembleIcalFailure?> failure(http.Response response) async {
          try {
            await SembleIcalClient(
              client: MockClient((_) async => response),
            ).bookings(link: link, from: from, to: to);
            return null;
          } on SembleIcalException catch (error) {
            return error.failure;
          }
        }

        expect(
          await failure(http.Response('', 404)),
          SembleIcalFailure.rejected,
        );
        expect(
          await failure(http.Response('', 503)),
          SembleIcalFailure.unreachable,
        );
        expect(
          await failure(http.Response('<html></html>', 200)),
          SembleIcalFailure.badResponse,
        );
      },
    );
  });

  group('riserva senza chiave', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('chiave rifiutata: ultime regole e visite dal link iCal', () async {
      final settings = SembleSettings();
      await settings.save(key: 'old-key', userId: 'user1', doctorName: 'Test');
      // A good read on an earlier day left rules and bookings on the phone.
      var api = 0;
      var keyWorks = true;
      var linkWorks = true;
      final readAt = DateTime(2026, 10, 27, 9);
      SembleLayer layer() => SembleLayer(
        zoneShift: (_) => 0,
        settings: settings,
        client: SembleClient(
          client: MockClient((request) async {
            api++;
            if (!keyWorks) return http.Response('', 401);
            final query =
                (jsonDecode(request.body) as Map<String, Object?>)['query']
                    as String;
            if (query.contains('bookings')) {
              return http.Response(
                jsonEncode({
                  'data': {
                    'bookings': {
                      'data': [
                        {
                          'start': '2026-10-30T15:00:00.000Z',
                          'end': '2026-10-30T15:30:00.000Z',
                          'deleted': false,
                          'doctorName': 'Dr Test',
                          'appointment': {'title': 'Follow-up 30'},
                        },
                      ],
                    },
                  },
                }),
                200,
              );
            }
            return rulesResponse();
          }),
        ),
        ical: SembleIcalClient(
          client: MockClient((_) async {
            if (!linkWorks) return http.Response('', 503);
            return http.Response(
              feed([
                event(':20261030T090000Z', end: ':20261030T093000Z'),
                event(':20261031T090000Z', end: ':20261031T093000Z'),
              ]),
              200,
            );
          }),
        ),
      );

      final earlier = layer();
      await earlier.refresh(
        today: const CivilDate(2026, 10, 27),
        now: () => readAt,
      );
      expect(earlier.bookingsSource, SembleBookingsSource.api);
      expect(earlier.bookingCount, 1);

      // The key is revoked; the app starts again.
      keyWorks = false;
      api = 0;
      var now = DateTime(2026, 10, 29, 8);
      final cold = layer();
      await cold.refresh(today: thu29, now: () => now);
      expect(cold.failure, SembleFailure.rejected);
      expect(cold.rulesFromCache, isTrue);
      expect(cold.rulesSavedAt, readAt);
      expect(cold.bandsFor(thu29), hasLength(1));
      expect(cold.canBlock, isFalse);
      // Without a link the visits are the Google copy only: no old
      // booking that may have been cancelled since.
      expect(cold.bookingsSource, SembleBookingsSource.google);
      expect(cold.bookingCount, 0);
      expect(cold.bookingsSavedAt, isNull);
      expect(api, 1, reason: 'una sola richiesta: niente prenotazioni');

      // A refused key is not asked again on every Calendar load.
      now = now.add(const Duration(minutes: 5));
      await cold.refresh(today: thu29, now: () => now);
      expect(api, 1);

      await settings.saveIcalLink(link);
      await cold.refresh(today: thu29, force: true, now: () => now);
      expect(cold.bookingsSource, SembleBookingsSource.ical);
      expect(cold.bookingCount, 2);
      expect(cold.bandsFor(thu29), hasLength(1));

      // Link down too: back to the Google copy.
      linkWorks = false;
      await cold.refresh(today: thu29, force: true, now: () => now);
      expect(cold.icalFailure, SembleIcalFailure.unreachable);
      expect(cold.bookingsSource, SembleBookingsSource.google);
      expect(cold.bookingCount, 0);
    });

    test('le visite salvate dalla build 312 vengono eliminate', () async {
      FlutterSecureStorage.setMockInitialValues({
        'semble_bookings_cache': '{"savedAt":"2026-10-29T08:00:00Z"}',
      });
      const storage = FlutterSecureStorage();
      final settings = SembleSettings();
      await settings.save(key: 'k', userId: 'user1');
      final layer = SembleLayer(
        zoneShift: (_) => 0,
        settings: settings,
        client: SembleClient(
          client: MockClient((_) async => http.Response('', 401)),
        ),
      );
      await layer.refresh(today: thu29);
      expect(await storage.read(key: 'semble_bookings_cache'), isNull);
      expect(layer.bookingsSource, SembleBookingsSource.google);
    });

    test('solo link, senza chiave: visite e nessuna chiamata API', () async {
      final settings = SembleSettings();
      await settings.saveIcalLink(link);
      var api = 0;
      final layer = SembleLayer(
        zoneShift: (_) => 0,
        settings: settings,
        client: SembleClient(
          client: MockClient((_) async {
            api++;
            return http.Response('', 500);
          }),
        ),
        ical: SembleIcalClient(
          client: MockClient(
            (_) async => http.Response(
              feed([event(':20261030T090000Z', end: ':20261030T093000Z')]),
              200,
            ),
          ),
        ),
      );
      await layer.refresh(today: thu29);
      expect(api, 0);
      expect(layer.bookingsSource, SembleBookingsSource.ical);
      expect(layer.bookingCount, 1);
      expect(layer.bandsFor(thu29), isEmpty, reason: 'nessuna regola letta');
      expect(layer.canBlock, isFalse);
      // A fresh feed hides a Google copy it no longer has (build 314).
      const calendars = [
        AgendaCalendar(id: 'semble', name: 'Semble', accountName: ''),
      ];
      final gone = DateTime.now().add(const Duration(days: 3));
      final adjusted = layer.adjustEntries(calendars, const {})!([
        AgendaEntry(
          instanceId: 'gone',
          calendarIds: const ['semble'],
          title: "Follow-up 30'",
          start: gone,
          end: gone.add(const Duration(minutes: 30)),
          allDay: false,
        ),
      ]);
      expect(adjusted.map((e) => e.instanceId), isNot(contains('gone')));

      await settings.deleteIcalLink();
      await layer.reset(today: thu29);
      expect(layer.bookingCount, 0);
      expect(layer.active, isFalse);
    });

    test('eliminare la chiave lascia il link', () async {
      final settings = SembleSettings();
      await settings.save(key: 'k', userId: 'user1');
      await settings.saveIcalLink(link);
      await settings.saveRules(
        const [],
        thu29,
        thu29.addDays(1),
        savedAt: DateTime(2026, 10, 29),
      );
      expect((await settings.cachedRules())!.savedAt, DateTime(2026, 10, 29));
      await settings.clear();
      expect(await settings.icalLink(), link);
      expect(await settings.cachedRules(), isNull);
      expect(
        () => settings.saveIcalLink('http://example.test/a.ics'),
        throwsFormatException,
      );
    });
  });

  test('le regole salvate prima della build 312 restano leggibili', () async {
    FlutterSecureStorage.setMockInitialValues({
      'semble_rules_cache': jsonEncode({
        'first': '2026-10-22',
        'last': '2027-01-22',
        'rules': [rule()],
      }),
    });
    final cache = (await SembleSettings().cachedRules())!;
    expect(cache.savedAt, isNull);
    expect(cache.rules.single, isA<SembleRule>());
    expect(sembleBandsFor(cache.rules, thu29), hasLength(1));
  });

  test('una visita annullata nel feed non diventa una visita', () {
    final booking = parseSembleIcal(
      feed([
        event(
          ':20261103T090000Z',
          end: ':20261103T093000Z',
          extra: 'STATUS:CANCELLED',
        ),
      ]),
      from: from,
      to: to,
    ).single;
    expect(booking.outcome, SembleOutcome.cancelled);
  });

  testWidgets('chiave rifiutata: la pagina propone il link e lo salva', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final settings = SembleSettings();
    await settings.save(key: 'old-key', userId: 'user1');
    final layer = SembleLayer(
      zoneShift: (_) => 0,
      settings: settings,
      client: SembleClient(
        client: MockClient((_) async => http.Response('', 401)),
      ),
      ical: SembleIcalClient(
        client: MockClient(
          (_) async => http.Response(
            feed([event(':20261030T090000Z', end: ':20261030T093000Z')]),
            200,
          ),
        ),
      ),
    );
    await layer.refresh(today: thu29, now: () => DateTime(2026, 10, 29, 9));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SembleSettingsView(
          settings: settings,
          layer: layer,
          now: () => DateTime(2026, 10, 29, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('rifiutato la chiave'), findsOne);
    expect(find.textContaining('dal calendario Google «Semble»'), findsOne);
    const calendars = [
      AgendaCalendar(id: 'semble', name: 'Semble', accountName: ''),
    ];
    layer.adjustEntries(calendars, const {'semble'});
    expect(layer.googleCalendarVisible, isFalse);
    layer.adjustEntries(calendars, const {});
    expect(layer.googleCalendarVisible, isTrue);
    // Opened by itself, since the key is refused and no link is saved.
    await tester.enterText(
      find.byKey(const ValueKey('semble-ical-input')),
      'http://example.test/a.ics',
    );
    await tester.tap(find.byKey(const ValueKey('semble-ical-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Link iCal non valido'), findsOne);
    expect(await settings.icalLink(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('semble-ical-input')),
      link,
    );
    await tester.tap(find.byKey(const ValueKey('semble-ical-save')));
    await tester.pumpAndSettle();
    expect(await settings.icalLink(), link);
    expect(find.textContaining('Lette 1 visite'), findsOne);
    expect(find.textContaining('visite dal link iCal'), findsOne);
    expect(find.text(link), findsNothing, reason: 'il link non si mostra');
  });

  group('allineato allo script (build 314)', () {
    test('titoli come nel calendario Google', () {
      expect(
        sembleIcalTitle('Follow-up Consultation (30 minutes) - Vitality'),
        "Follow-up 30' · Vitality",
      );
      expect(
        sembleIcalTitle(
          'Room - Initial Consultation (Child & Adolescent) (60 minutes) - AVIVA',
        ),
        "Prima visita (minore) 60' · AVIVA",
      );
      expect(
        sembleIcalTitle(
          'Online Psychiatry - Urgent Follow-up Consultation 15 min',
        ),
        "Follow-up urgente 15'",
      );
      expect(
        sembleIcalTitle('ADHD Assessment (Adult) (75 minutes) - (PLE)'),
        "ADHD Assessment (Adult) 75' · (PLE)",
      );
      expect(sembleIcalTitle('Visita'), 'Visita');
    });

    test('ricette e lettere non sono visite', () {
      final bookings = parseSembleIcal(
        feed([
          event(
            ':20261030T090000Z',
            end: ':20261030T091500Z',
            summary: 'Repeat Prescription',
          ),
          event(
            ':20261030T100000Z',
            end: ':20261030T101500Z',
            summary: 'Reports & Letters',
          ),
          event(
            ':20261030T110000Z',
            end: ':20261030T114500Z',
            summary: 'Follow-up Consultation (30 minutes)',
          ),
        ]),
        from: from,
        to: to,
      );
      expect(bookings.map((b) => b.appointmentTitle), ["Follow-up 30'"]);
    });

    group('copie Google spostate o annullate', () {
      const calendars = [
        AgendaCalendar(id: 'semble', name: 'Semble', accountName: ''),
        AgendaCalendar(id: 'kcl', name: 'KCL', accountName: ''),
      ];
      final now = DateTime(2026, 10, 31, 9);
      final until = DateTime(2026, 11, 29);
      AgendaEntry copy(
        String id,
        DateTime start, {
        String calendar = 'semble',
      }) => AgendaEntry(
        instanceId: id,
        calendarIds: [calendar],
        title: "Follow-up 30'",
        start: start,
        end: start.add(const Duration(minutes: 30)),
        allDay: false,
      );
      SembleBooking booking(DateTime start) => SembleBooking(
        start: start,
        end: start.add(const Duration(minutes: 45)),
        deleted: false,
        appointmentTitle: "Follow-up 30'",
      );
      List<String> ids(List<AgendaEntry> entries) => [
        for (final e in entries) e.instanceId,
      ];

      test(
        'nascoste solo le future del calendario Semble assenti dal feed',
        () {
          final kept = DateTime(2026, 11, 2, 11);
          final moved = DateTime(2026, 11, 3, 11);
          final merged = [
            copy('past', DateTime(2026, 10, 30, 11)),
            copy('kept', kept),
            copy('moved', moved),
            copy('kcl', moved.add(const Duration(hours: 2)), calendar: 'kcl'),
            copy('far', DateTime(2026, 12, 10, 11)),
          ];
          final newTime = moved.add(const Duration(hours: 1));
          final result = sembleAdjustEntries(
            bookings: [booking(kept), booking(newTime)],
            merged: merged,
            calendars: calendars,
            hiddenCalendarIds: const {},
            now: now,
            feedUntil: until,
          );
          expect(ids(result), containsAll(['past', 'kept', 'kcl', 'far']));
          expect(ids(result), isNot(contains('moved')));
          // The new time comes from the feed until the script moves the copy.
          expect(
            result.where((e) => e.start == newTime && e.isSembleBooking),
            hasLength(1),
          );
          // Without the feed (API or Google only) nothing is hidden.
          expect(
            ids(
              sembleAdjustEntries(
                bookings: [booking(kept), booking(newTime)],
                merged: merged,
                calendars: calendars,
                hiddenCalendarIds: const {},
                now: now,
              ),
            ),
            contains('moved'),
          );
        },
      );

      test('più di 5 copie da nascondere: feed sospetto, nessuna', () {
        final merged = [
          for (var day = 1; day <= 6; day++)
            copy('c$day', DateTime(2026, 11, day, 11)),
        ];
        final result = sembleAdjustEntries(
          bookings: [booking(DateTime(2026, 11, 20, 9))],
          merged: merged,
          calendars: calendars,
          hiddenCalendarIds: const {},
          now: now,
          feedUntil: until,
        );
        expect(ids(result), containsAll([for (var d = 1; d <= 6; d++) 'c$d']));
        expect(
          ids(
            sembleAdjustEntries(
              bookings: [booking(DateTime(2026, 11, 20, 9))],
              merged: merged.take(5).toList(),
              calendars: calendars,
              hiddenCalendarIds: const {},
              now: now,
              feedUntil: until,
            ),
          ).where((id) => id.startsWith('c')),
          isEmpty,
        );
      });
    });
  });

  testWidgets('Copia chiave: conferma, appunti, svuotati dopo un minuto', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final settings = SembleSettings();
    await settings.save(key: 'secret-copy-1234', userId: 'user1');
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final layer = SembleLayer(
      zoneShift: (_) => 0,
      settings: settings,
      client: SembleClient(
        client: MockClient((_) async => http.Response('', 401)),
      ),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SembleSettingsView(settings: settings, layer: layer),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('semble-copy-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(clipboard, isNull, reason: 'senza conferma non copia');

    await tester.tap(find.byKey(const ValueKey('semble-copy-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('semble-confirm-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, 'secret-copy-1234');
    expect(find.textContaining('Chiave copiata'), findsOne);
    expect(find.text('secret-copy-1234'), findsNothing);

    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(clipboard, '');
  });

  group('blocchi creati da Todo (build 317)', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    const block = SembleTodoBlock(
      id: 'b1',
      date: CivilDate(2026, 11, 26),
      startTime: '08:00',
      endTime: '09:00',
    );

    test('salvati, ora di Londra convertita, potati', () async {
      final settings = SembleSettings();
      await settings.addTodoBlock(block);
      await settings.addTodoBlock(
        const SembleTodoBlock(
          id: 'b2',
          date: CivilDate(2026, 11, 27),
          startTime: '10:00',
          endTime: '24:00',
        ),
      );
      final saved = await settings.todoBlocks();
      expect(saved.map((b) => b.id), ['b1', 'b2']);
      // GMT in November: 08:00 London is 08:00 UTC.
      expect(saved.first.start.toUtc(), DateTime.utc(2026, 11, 26, 8));
      expect(saved.last.end.toUtc(), DateTime.utc(2026, 11, 28));

      // Read window covers b1 only and Semble still has it.
      await settings.pruneTodoBlocks(
        ruleIds: {'b1'},
        first: const CivilDate(2026, 11, 1),
        last: const CivilDate(2026, 11, 26),
        now: DateTime.utc(2026, 11, 3),
      );
      expect((await settings.todoBlocks()).map((b) => b.id), ['b1', 'b2']);
      // Removed in Semble itself: gone from the list.
      await settings.pruneTodoBlocks(
        ruleIds: const {},
        first: const CivilDate(2026, 11, 1),
        last: const CivilDate(2026, 11, 26),
        now: DateTime.utc(2026, 11, 3),
      );
      expect((await settings.todoBlocks()).map((b) => b.id), ['b2']);
      // Over: gone too.
      await settings.pruneTodoBlocks(
        ruleIds: {'b2'},
        first: const CivilDate(2026, 11, 1),
        last: const CivilDate(2026, 12, 31),
        now: DateTime.utc(2026, 11, 29),
      );
      expect(await settings.todoBlocks(), isEmpty);
      await settings.addTodoBlock(block);
      await settings.removeTodoBlock('b1');
      expect(await settings.todoBlocks(), isEmpty);
    });

    testWidgets('Rimuovi chiede conferma e cancella proprio quel blocco', (
      tester,
    ) async {
      final settings = SembleSettings();
      await settings.save(key: 'k', userId: 'user1', roomId: 'room1');
      await settings.addTodoBlock(block);
      final deleted = <Object?>[];
      final client = SembleClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['query'] == sembleDeleteBlockMutation) {
            deleted.add((body['variables'] as Map)['id']);
            return http.Response(
              jsonEncode({
                'data': {
                  'deleteAvailability': {
                    'data': {'id': 'b1'},
                  },
                },
              }),
              200,
            );
          }
          return rulesResponse();
        }),
      );
      final layer = SembleLayer(
        zoneShift: (_) => 0,
        settings: settings,
        client: client,
      );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SembleSettingsView(
            settings: settings,
            layer: layer,
            client: client,
            now: () => DateTime(2026, 11, 3, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Blocchi creati da Todo'), findsOne);
      expect(find.textContaining('08:00–09:00, ora di Londra'), findsOne);

      await tester.tap(find.byKey(const ValueKey('semble-remove-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);

      await tester.tap(find.byKey(const ValueKey('semble-remove-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('semble-confirm-remove')));
      await tester.pumpAndSettle();
      expect(deleted, ['b1']);
      expect(await settings.todoBlocks(), isEmpty);
      expect(find.text('Blocco rimosso da Semble.'), findsOne);
      expect(find.text('Blocchi creati da Todo'), findsNothing);
    });
  });

  group('orari liberi da Semble (build 318)', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('ora di Londra, slot vicini uniti, righe dalle regole', () {
      // GMT in November: London wall clock equals UTC.
      expect(
        sembleLocalTime('2026-11-03T10:00:00')!.toUtc(),
        DateTime.utc(2026, 11, 3, 10),
      );
      const day = CivilDate(2026, 11, 3);
      SembleSlot slot(int h, int m, int minutes) {
        final start = DateTime.utc(2026, 11, 3, h, m).toLocal();
        return (start: start, end: start.add(Duration(minutes: minutes)));
      }

      final local = DateTime.utc(2026, 11, 3, 15, 15).toLocal();
      final from = local.difference(day.asLocalDate).inMinutes;
      final bands = sembleSlotBands(
        const [
          SembleBand(SembleBandKind.available, 0, 24 * 60),
          SembleBand(SembleBandKind.unavailable, 60, 120),
        ],
        [slot(15, 15, 15), slot(15, 30, 60)],
        day,
      );
      expect(bands, [
        const SembleBand(SembleBandKind.unavailable, 60, 120),
        SembleBand(SembleBandKind.available, from, from + 75),
      ]);
    });

    test('il livello usa gli slot e torna alle regole se mancano', () async {
      final settings = SembleSettings();
      await settings.save(key: 'k', userId: 'user1');
      var slotsWork = true;
      final today = CivilDate.fromDateTime(DateTime.now());
      final slotStart = DateTime(today.year, today.month, today.day, 9);
      String london(DateTime local) =>
          londonDigitsOf(local).toIso8601String().replaceFirst('.000Z', '');
      final layer = SembleLayer(
        zoneShift: (_) => 0,
        settings: settings,
        client: SembleClient(
          client: MockClient((request) async {
            if (request.body.contains('availabilitySlots(')) {
              if (!slotsWork) return http.Response('', 500);
              return http.Response(
                jsonEncode({
                  'data': {
                    'availabilitySlots': {
                      'data': [
                        {
                          'startLocal': london(slotStart),
                          'endLocal': london(
                            slotStart.add(const Duration(minutes: 30)),
                          ),
                        },
                      ],
                      'pageInfo': {'hasMore': false},
                    },
                  },
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'availabilityRules': {
                    'data': [
                      {
                        ...rule(),
                        'startTime': '00:00',
                        'endTime': '23:45',
                        'recurrence': {
                          'frequency': 'daily',
                          'interval': 1,
                          'daysOfTheWeek': <int>[],
                        },
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }),
        ),
      );
      await layer.refresh(today: today, force: true);
      expect(layer.slotsActive, isTrue);
      final green = layer
          .bandsFor(today)
          .where((b) => b.kind == SembleBandKind.available)
          .toList();
      expect(green.single.startMinute, 9 * 60);
      expect(green.single.endMinute, 9 * 60 + 30);

      slotsWork = false;
      await layer.refresh(today: today, force: true);
      expect(layer.slotsActive, isFalse);
      expect(
        layer
            .bandsFor(today)
            .where((b) => b.kind == SembleBandKind.available)
            .single
            .endMinute,
        greaterThan(9 * 60 + 30),
        reason: 'senza slot il verde viene dalle regole',
      );
    });
  });
}
