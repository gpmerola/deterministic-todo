import 'dart:convert';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:deterministic_todo/ui/semble_settings_view.dart';
import 'package:deterministic_todo/ui/views/agenda_semble_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

// Synthetic rules shaped like the ones Semble returned on 22 October 2026;
// ids are made up.
Map<String, Object?> weekly(
  String id,
  List<int> days,
  String start,
  String end, {
  String startDate = '2026-01-05',
  String? endDate,
  int interval = 1,
  List<String> exclusions = const [],
}) => {
  'id': id,
  'unavailability': false,
  'startDate': startDate,
  'endDate': endDate,
  'startTime': start,
  'endTime': end,
  'exclusions': exclusions,
  'recurrence': {
    'frequency': 'weekly',
    'interval': interval,
    'daysOfTheWeek': days,
  },
};

Map<String, Object?> once(
  String id,
  String date,
  String start,
  String end, {
  bool unavailability = true,
}) => {
  'id': id,
  'unavailability': unavailability,
  'startDate': date,
  'endDate': null,
  'startTime': start,
  'endTime': end,
  'recurrence': null,
};

List<SembleRule> parse(List<Map<String, Object?>> json) =>
    json.map(SembleRule.fromJson).whereType<SembleRule>().toList();

const thu22 = CivilDate(2026, 10, 22);
const fri23 = CivilDate(2026, 10, 23);
const mon26 = CivilDate(2026, 10, 26);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('regole', () {
    test('ricorrenza settimanale con 0 = domenica', () {
      final rules = parse([
        weekly('a', [4], '10:00', '18:00'),
        weekly('b', [0], '10:00', '18:00'),
      ]);
      expect(sembleBandsFor(rules, thu22), [
        const SembleBand(SembleBandKind.available, 600, 1080),
      ]);
      expect(sembleBandsFor(rules, const CivilDate(2026, 10, 25)), [
        const SembleBand(SembleBandKind.available, 600, 1080),
      ]);
      expect(sembleBandsFor(rules, fri23), isEmpty);
    });

    test('le indisponibilità tagliano la disponibilità e restano visibili', () {
      final rules = parse([
        weekly('a', [4], '10:00', '18:00'),
        once('x', '2026-10-22', '14:00', '15:00'),
        once('y', '2026-10-22', '17:00', '18:00'),
        once('z', '2026-10-22', '18:00', '23:45'),
      ]);
      expect(sembleBandsFor(rules, thu22), [
        const SembleBand(SembleBandKind.available, 600, 840),
        const SembleBand(SembleBandKind.unavailable, 840, 900),
        const SembleBand(SembleBandKind.available, 900, 1020),
        const SembleBand(SembleBandKind.unavailable, 1020, 1425),
      ]);
      // A one-off rule without an end date covers its own day only.
      expect(sembleBandsFor(rules, const CivilDate(2026, 10, 29)), [
        const SembleBand(SembleBandKind.available, 600, 1080),
      ]);
    });

    test('venerdì con due fasce e disponibilità aggiuntiva una tantum', () {
      final rules = parse([
        weekly('a', [5], '10:00', '13:00'),
        weekly('b', [5], '16:00', '18:00'),
        once('c', '2026-10-23', '12:00', '16:30', unavailability: false),
      ]);
      expect(sembleBandsFor(rules, fri23), [
        const SembleBand(SembleBandKind.available, 600, 1080),
      ]);
    });

    test('esclusioni, data di fine, intervallo e date ISO', () {
      final rules = parse([
        weekly(
          'a',
          [1],
          '10:00',
          '18:00',
          startDate: '2026-10-05T00:00:00.000Z',
          endDate: '2026-11-30',
          interval: 2,
          exclusions: ['2026-11-02'],
        ),
      ]);
      expect(sembleBandsFor(rules, const CivilDate(2026, 10, 5)), isNotEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 10, 12)), isEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 10, 19)), isNotEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 11, 2)), isEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 11, 16)), isNotEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 12, 14)), isEmpty);
      expect(sembleBandsFor(rules, const CivilDate(2026, 9, 28)), isEmpty);
    });

    test('forme sconosciute sono escluse, non indovinate', () {
      expect(
        SembleRule.fromJson({
          ...weekly('a', [1], '10:00', '18:00'),
          'recurrence': {'frequency': 'monthly', 'interval': 1},
        }),
        isNull,
      );
      expect(SembleRule.fromJson(once('b', 'ieri', '10:00', '11:00')), isNull);
      expect(
        SembleRule.fromJson(once('c', '2026-10-22', '11:00', '10:00')),
        isNull,
      );
      expect(
        SembleRule.fromJson(
          once('d', '2026-10-22', '18:00', '24:00'),
        )!.endMinute,
        1440,
      );
    });
  });

  group('client', () {
    test('legge con x-token, senza mutazioni né stanza, e pagina', () async {
      final requests = <http.Request>[];
      final client = SembleClient(
        client: MockClient((request) async {
          requests.add(request);
          final page =
              ((jsonDecode(request.body) as Map)['variables'] as Map)['page']
                  as Map;
          final count = page['page'] == 1 ? SembleClient.pageSize : 3;
          return http.Response(
            jsonEncode({
              'data': {
                'availabilityRules': {
                  'data': [
                    for (var i = 0; i < count; i++)
                      weekly('p${page['page']}-$i', [1], '10:00', '18:00'),
                  ],
                },
              },
            }),
            200,
          );
        }),
      );
      final rules = await client.rules(
        key: 'secret',
        userId: 'user1',
        first: thu22,
        last: thu22,
      );
      expect(rules, hasLength(SembleClient.pageSize + 3));
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.url.toString(), sembleEndpoint);
        expect(request.headers['x-token'], 'secret');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final query = body['query']! as String;
        expect(query, isNot(contains('mutation')));
        expect(query, isNot(contains('room')));
        expect(query, isNot(contains('comment')));
        final variables = body['variables']! as Map;
        expect(variables['userIds'], ['user1']);
        // Semble rejects end == start: the end is the next day.
        expect(variables['range'], {
          'start': '2026-10-22',
          'end': '2026-10-23',
        });
      }
    });

    test('classifica gli errori GraphQL e riprova senza exclusions', () async {
      Future<SembleFailure?> failureFor(Object body, [int status = 200]) async {
        try {
          await SembleClient(
            client: MockClient(
              (_) async => http.Response(jsonEncode(body), status),
            ),
          ).check('k');
          return null;
        } on SembleException catch (error) {
          return error.failure;
        }
      }

      Map<String, Object?> error(String code) => {
        'errors': [
          {
            'message': 'x',
            'extensions': {'code': code},
          },
        ],
      };
      expect(await failureFor(error('FORBIDDEN')), SembleFailure.forbidden);
      expect(
        await failureFor(error('UNAUTHENTICATED'), 401),
        SembleFailure.rejected,
      );
      expect(
        await failureFor(error('UNAUTHENTICATED')),
        SembleFailure.rejected,
      );
      expect(await failureFor({'data': {}}), isNull);

      final queries = <String>[];
      final rules = await SembleClient(
        client: MockClient((request) async {
          final query = (jsonDecode(request.body) as Map)['query'] as String;
          queries.add(query);
          if (query.contains('exclusions')) {
            return http.Response(
              jsonEncode({
                'errors': [
                  {
                    'message':
                        'Field "exclusions" of type "[X!]!" must have a '
                        'selection of subfields.',
                    'extensions': {'code': 'GRAPHQL_VALIDATION_FAILED'},
                  },
                ],
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'data': {
                'availabilityRules': {
                  'data': [
                    weekly('a', [1], '10:00', '18:00'),
                  ],
                },
              },
            }),
            200,
          );
        }),
      ).rules(key: 'k', userId: 'u', first: thu22, last: mon26);
      expect(rules, hasLength(1));
      expect(queries, hasLength(2));
      expect(queries.last, isNot(contains('exclusions')));
    });
  });

  group('livello', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('impostazioni nel Keystore e lettura limitata nel tempo', () async {
      final settings = SembleSettings();
      var calls = 0;
      final layer = SembleLayer(
        settings: settings,
        client: SembleClient(
          client: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode({
                'data': {
                  'availabilityRules': {
                    'data': [
                      weekly('a', [4], '10:00', '18:00'),
                    ],
                  },
                },
              }),
              200,
            );
          }),
        ),
      );
      await layer.refresh(today: thu22, zoneLabel: 'Europe/London · UTC+1');
      expect(calls, 0, reason: 'nessuna chiave: nessuna richiesta');
      expect(layer.bandsFor(thu22), isEmpty);

      await settings.save(key: ' secret-9876 ', userId: 'user1');
      expect((await settings.read()).maskedKey, '…9876');
      var now = DateTime(2026, 10, 22, 9);
      await layer.refresh(today: thu22, zoneLabel: null, now: () => now);
      expect(calls, 1);
      expect(layer.bandsFor(thu22), hasLength(1));
      // Outside the window read: nothing, rather than an incomplete layer.
      expect(layer.bandsFor(thu22.addDays(SembleLayer.daysAhead + 7)), isEmpty);

      now = now.add(const Duration(minutes: 5));
      await layer.refresh(today: thu22, now: () => now);
      expect(calls, 1);
      await layer.refresh(today: thu22, force: true, now: () => now);
      expect(calls, 2);

      await layer.refresh(
        today: thu22,
        zoneLabel: 'Europe/Rome · UTC+2',
        now: () => now,
      );
      expect(layer.bandsFor(thu22), isEmpty);
      await layer.refresh(
        today: thu22,
        zoneLabel: 'Europe/London · UTC+1',
        now: () => now,
      );
      expect(layer.bandsFor(thu22), hasLength(1));

      await settings.setEnabled(false);
      await layer.refresh(today: thu22, force: true, now: () => now);
      expect(layer.bandsFor(thu22), isEmpty);
      expect(calls, 2);
    });

    testWidgets('le fasce si disegnano dietro agli eventi', (tester) async {
      final layer = SembleLayer()
        ..seed(
          parse([
            weekly('a', [4], '10:00', '18:00'),
          ]),
          thu22,
          mon26,
        );
      final scale = TimelineScale.forBlocks(const [], hourHeight: 48);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 1200,
            child: Stack(
              children: [
                AgendaSembleBands(day: thu22, scale: scale, layer: layer),
                AgendaSembleBands(day: fri23, scale: scale, layer: layer),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('agenda-semble-2026-10-22')), findsOne);
      expect(
        find.byKey(const ValueKey('agenda-semble-2026-10-23')),
        findsNothing,
      );
    });
  });

  group('impostazioni', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('una chiave rifiutata non viene salvata', (tester) async {
      var accept = false;
      final client = SembleClient(
        client: MockClient(
          (request) async => accept
              ? http.Response(
                  jsonEncode({
                    'data': {
                      '__typename': 'Query',
                      'availabilityRules': {'data': <Object?>[]},
                    },
                  }),
                  200,
                )
              : http.Response('{"errors":[]}', 401),
        ),
      );
      final settings = SembleSettings();
      final layer = SembleLayer(settings: settings, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: SembleSettingsView(
            settings: settings,
            layer: layer,
            client: client,
            now: () => DateTime(2026, 10, 22, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('semble-user-input')),
        'user1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semble-key-input')),
        'secret-1234',
      );
      await tester.tap(find.byKey(const ValueKey('semble-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('rifiutato'), findsOne);
      expect(await settings.apiKey(), isNull);

      accept = true;
      await tester.tap(find.byKey(const ValueKey('semble-save')));
      await tester.pumpAndSettle();
      expect(await settings.apiKey(), 'secret-1234');
      expect(find.text('Chiave …1234'), findsOne);
      expect(find.textContaining('Lette 0 regole'), findsOne);
    });
  });
}
