import 'dart:convert';

import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/semble_bookings.dart';
import 'package:deterministic_todo/domain/semble_ical.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:deterministic_todo/ui/semble_settings_view.dart';
import 'package:flutter/material.dart';
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
      // Without a link: the bookings saved by the good read.
      expect(cold.bookingsSource, SembleBookingsSource.saved);
      expect(cold.bookingCount, 1);
      expect(cold.bookingsSavedAt, readAt);
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

      // Link down too: the iCal bookings stay, marked as saved.
      linkWorks = false;
      await cold.refresh(today: thu29, force: true, now: () => now);
      expect(cold.icalFailure, SembleIcalFailure.unreachable);
      expect(cold.bookingsSource, SembleBookingsSource.saved);
      expect(cold.bookingCount, 2);

      // A new app session reads them back from the phone.
      final again = layer();
      await again.refresh(today: thu29, now: () => now);
      expect(again.bookingsSource, SembleBookingsSource.saved);
      expect(again.bookingCount, 2);
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
      expect(await settings.cachedBookings(), isNull);
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
}
