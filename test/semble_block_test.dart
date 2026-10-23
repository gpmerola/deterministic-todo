import 'dart:convert';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/semble_bookings.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:deterministic_todo/ui/semble_block_sheet.dart';
import 'package:deterministic_todo/ui/views/agenda_event_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

// Synthetic ids only; no real Semble data.
const _created = {
  'data': {
    'createAvailability': {
      'data': {'id': 'block1'},
    },
  },
};

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('orari del blocco', () {
    test('ora di Londra, un solo giorno, 24:00 ammesso', () {
      // 14:00–15:00 London in BST is 13:00–14:00 UTC.
      final start = DateTime.utc(2026, 10, 23, 13).toLocal();
      final block = sembleBlockFor(start, start.add(const Duration(hours: 1)))!;
      expect(block.date, const CivilDate(2026, 10, 23));
      expect(block.startTime, '14:00');
      expect(block.endTime, '15:00');
      final winter = DateTime.utc(2026, 11, 10, 23).toLocal();
      expect(
        sembleBlockFor(winter, winter.add(const Duration(hours: 1)))!.endTime,
        '24:00',
      );
      expect(
        sembleBlockFor(winter, winter.add(const Duration(hours: 2))),
        isNull,
      );
      expect(sembleBlockFor(start, start), isNull);
    });
  });

  group('client', () {
    test('crea senza endDate e cancella solo quell id', () async {
      final bodies = <Map<String, Object?>>[];
      final client = SembleClient(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response(
            jsonEncode(
              bodies.length == 1
                  ? _created
                  : {
                      'data': {
                        'deleteAvailability': {
                          'data': {'id': 'block1'},
                        },
                      },
                    },
            ),
            200,
          );
        }),
      );
      final start = DateTime.utc(2026, 10, 23, 13).toLocal();
      final id = await client.createUnavailability(
        key: 'k',
        userId: 'user1',
        roomId: 'room1',
        start: start,
        end: start.add(const Duration(minutes: 30)),
        type: SembleBlockType.clinicalAdmin,
      );
      expect(id, 'block1');
      expect(bodies.single['query'], sembleCreateBlockMutation);
      expect(bodies.single['variables'], {
        'data': {
          'unavailability': true,
          'room': 'room1',
          'user': 'user1',
          'startDate': '2026-10-23',
          'startTime': '14:00',
          'endTime': '14:30',
          'unavailabilityType': 'clinicalAdmin',
          'comment': sembleBlockComment,
        },
      });
      await client.deleteUnavailability(key: 'k', id: id);
      expect(bodies.last['query'], sembleDeleteBlockMutation);
      expect(bodies.last['variables'], {'id': 'block1'});
    });
  });

  group('interfaccia', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('conferma, blocco creato e Annulla lo cancella', (
      tester,
    ) async {
      final settings = SembleSettings();
      expect(await sembleBlockReady(settings), isFalse);
      await settings.save(key: 'k', userId: 'user1', roomId: 'room1');
      expect(await sembleBlockReady(settings), isTrue);
      final queries = <String>[];
      final client = SembleClient(
        client: MockClient((request) async {
          final query = (jsonDecode(request.body) as Map)['query'] as String;
          queries.add(query);
          return http.Response(
            jsonEncode(
              query == sembleCreateBlockMutation
                  ? _created
                  : {
                      'data': {
                        'deleteAvailability': {
                          'data': {'id': 'block1'},
                        },
                        'availabilityRules': {'data': <Object?>[]},
                        'bookings': {
                          'data': <Object?>[],
                          'pageInfo': {'hasMore': false},
                        },
                      },
                    },
            ),
            200,
          );
        }),
      );
      final layer = SembleLayer(
        settings: settings,
        client: client,
        zoneShift: (_) => 0,
      );
      await layer.refresh(today: const CivilDate(2026, 10, 23), force: true);
      expect(layer.canBlock, isTrue);
      queries.clear();
      bool? result;
      final start = DateTime(2026, 10, 23, 14);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showSembleBlockSheet(
                  context,
                  start: start,
                  end: start.add(const Duration(hours: 1)),
                  settings: settings,
                  client: client,
                  layer: layer,
                ),
                child: const Text('blocca'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('blocca'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('semble-block-sheet')), findsOne);
      expect(queries, isEmpty, reason: 'nulla prima della conferma');
      await tester.tap(find.byKey(const ValueKey('semble-block-cpd')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('semble-block-confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(queries.first, sembleCreateBlockMutation);
      expect(queries.where((q) => q.startsWith('mutation')), hasLength(1));
      expect(find.text('Bloccato in Semble.'), findsOne);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(
        queries.where((q) => q == sembleDeleteBlockMutation),
        hasLength(1),
      );
      expect(find.text('Blocco Semble annullato.'), findsOne);
    });

    testWidgets('dal nuovo evento: blocca con gli orari del modulo', (
      tester,
    ) async {
      final blocked = <(DateTime, DateTime)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<AgendaEventDraft>(
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
                    initialStart: DateTime(2026, 10, 23, 14),
                    initialEnd: DateTime(2026, 10, 23, 15, 30),
                    zoneLabel: 'Europe/London · UTC+1',
                    onSembleBlock: (start, end) async {
                      blocked.add((start, end));
                      return true;
                    },
                  ),
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-event-semble-block')));
      await tester.pumpAndSettle();
      expect(blocked, [
        (DateTime(2026, 10, 23, 14), DateTime(2026, 10, 23, 15, 30)),
      ]);
      expect(find.byType(AgendaEventEditor), findsNothing);
    });
  });
}
