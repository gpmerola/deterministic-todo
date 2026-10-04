import 'dart:convert';

import 'package:deterministic_todo/domain/ai_capture.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/ai_settings.dart';
import 'package:deterministic_todo/ui/ai_capture_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

final context = AiCaptureContext(
  now: DateTime(2026, 10, 5, 9, 30),
  zoneLabel: 'Europe/London · UTC+1',
  projects: const [
    (id: 'p-admin', name: 'Admin'),
    (id: 'p-res', name: 'Ricerca'),
  ],
  calendars: const [
    (id: 'cal-g', name: 'sennar.pierp@gmail.com'),
    (id: 'cal-kcl', name: 'Calendario'),
  ],
  defaultCalendarId: 'cal-g',
  upcoming: [
    (
      title: 'TNG Meeting',
      start: DateTime(2026, 10, 8, 15, 30),
      end: DateTime(2026, 10, 8, 16, 30),
      allDay: false,
    ),
  ],
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('il marcatore ✨ è visibile e non si duplica', () {
    expect(markAiTitle(' Preparare slide '), '✨ Preparare slide');
    expect(markAiTitle('✨ Preparare slide'), '✨ Preparare slide');
    const task = AiProposal.task(
      title: 'x',
      notes: 'Portare dati',
      relatedEvent: 'TNG Meeting · gio 8 ott 15:30',
    );
    expect(
      task.storedNotes(),
      'Portare dati\n\nCollegata a: TNG Meeting · gio 8 ott 15:30\n\n$aiFooter',
    );
  });

  test('il contesto numera progetti, calendari ed eventi', () {
    final prompt = aiCaptureUserPrompt(context, '  slide per giovedì ');
    expect(prompt, contains('TODAY: Monday 2026-10-05 09:30'));
    expect(prompt, contains('P2: Ricerca'));
    expect(prompt, contains('C1: sennar.pierp@gmail.com (default)'));
    expect(prompt, contains('E1: Thu 2026-10-08 15:30-16:30 | TNG Meeting'));
    expect(prompt, endsWith('NOTE:\nslide per giovedì'));
    expect(aiCaptureSystemPrompt(), contains('json'));
  });

  test('valida la risposta e scarta ciò che non torna', () {
    final raw = '''```json
{"items":[
 {"type":"task","title":"Preparare slide TNG","date":"2026-10-07","project":"P2","related":"E1","notes":null},
 {"type":"event","title":"Visita","start":"2026-10-06T15:00","end":null,"all_day":false,"calendar":null,"location":"Maudsley"},
 {"type":"event","title":"Congresso","start":"2026-10-12","end":"2026-10-13","all_day":true,"calendar":"C2"},
 {"type":"task","title":"Senza data","date":null,"project":"P9"},
 {"type":"task","title":"","date":"2026-10-07"},
 {"type":"event","title":"Al contrario","start":"2026-10-06T16:00","end":"2026-10-06T15:00"},
 {"type":"task","title":"Troppo lontano","date":"2035-01-01"},
 {"type":"memo","title":"?"}
],"note":"Ho supposto giovedì 8."}
```''';
    final result = parseAiCapture(raw, context);
    expect(result.dropped, 4);
    expect(result.note, 'Ho supposto giovedì 8.');
    final [slides, visit, congress, undated] = result.items;
    expect(slides.kind, AiProposalKind.task);
    expect(slides.date, const CivilDate(2026, 10, 7));
    expect(slides.projectId, 'p-res');
    expect(slides.relatedEvent, 'TNG Meeting · gio 8 ott 15:30');
    expect(visit.calendarId, 'cal-g');
    expect(visit.end, DateTime(2026, 10, 6, 16));
    expect(visit.location, 'Maudsley');
    expect(congress.allDay, isTrue);
    expect(congress.calendarId, 'cal-kcl');
    expect(congress.end, DateTime(2026, 10, 14));
    expect(undated.date, isNull);
    expect(undated.projectId, isNull);
    expect(() => parseAiCapture('nessun json', context), throwsFormatException);
  });

  group('richieste al fornitore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('DeepSeek in modalità json, senza chiave nessuna richiesta', () async {
      final requests = <http.Request>[];
      final settings = AiSettings();
      final client = AiClient(
        settings,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"items":[]}'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(
        client.completeJson(system: 's', user: 'u'),
        throwsA(
          isA<AiException>().having((e) => e.failure, 'f', AiFailure.noKey),
        ),
      );
      expect(requests, isEmpty);

      await settings.save(AiProvider.deepseek, 'sk-1');
      expect(await client.completeJson(system: 's', user: 'u'), '{"items":[]}');
      final body = jsonDecode(requests.single.body) as Map;
      expect(
        requests.single.url.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(requests.single.headers['Authorization'], 'Bearer sk-1');
      expect(body['model'], 'deepseek-flash');
      expect(body['response_format'], {'type': 'json_object'});
      // Reasoning ran out of tokens on longer notes: off, more room.
      expect(body['thinking'], {'type': 'disabled'});
      expect(body['max_tokens'], 4096);
      expect((body['messages'] as List).first, {
        'role': 'system',
        'content': 's',
      });
    });

    test(
      'Claude legge i blocchi di testo; 401 diventa chiave rifiutata',
      () async {
        final settings = AiSettings();
        await settings.save(AiProvider.anthropic, 'sk-ant');
        var status = 200;
        final client = AiClient(
          settings,
          client: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://api.anthropic.com/v1/messages',
            );
            expect(
              (jsonDecode(request.body) as Map)['model'],
              'claude-haiku-4-5',
            );
            return http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': '{"items":'},
                  {'type': 'text', 'text': '[]}'},
                ],
              }),
              status,
            );
          }),
        );
        expect(
          await client.completeJson(system: 's', user: 'u'),
          '{"items":[]}',
        );
        status = 401;
        await expectLater(
          client.completeJson(system: 's', user: 'u'),
          throwsA(
            isA<AiException>().having(
              (e) => e.failure,
              'f',
              AiFailure.rejected,
            ),
          ),
        );
      },
    );
  });

  test('una risposta troncata ha un messaggio dedicato', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final settings = AiSettings();
    await settings.save(AiProvider.deepseek, 'sk-1');
    final client = AiClient(
      settings,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '{"items":[{"type":"ta'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      client.completeJson(system: 's', user: 'u'),
      throwsA(
        isA<AiException>().having((e) => e.failure, 'f', AiFailure.truncated),
      ),
    );
  });

  testWidgets('interpreta, si sceglie e si crea solo ciò che si conferma', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    final created = <AiProposal>[];
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AiCapturePage(
          client: _FakeClient(sent),
          providerLabel: 'DeepSeek',
          loadContext: () async => context,
          create: (items) async {
            created.addAll(items);
            return items.length;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-capture-input')),
      'slide per TNG giovedì e visita martedì 15',
    );
    await tester.tap(find.byKey(const ValueKey('ai-capture-interpret')));
    await tester.pumpAndSettle();
    expect(sent.single, contains('slide per TNG giovedì'));
    expect(find.text('✨ Preparare slide TNG'), findsOneWidget);
    expect(find.text('✨ Visita'), findsOneWidget);
    expect(find.textContaining('per TNG Meeting'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai-proposal-1')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-capture-create')));
    await tester.pumpAndSettle();
    expect(created.map((p) => p.title), ['Preparare slide TNG']);
  });
}

class _FakeClient extends AiClient {
  _FakeClient(this.sent) : super(AiSettings());
  final List<String> sent;

  @override
  Future<String> completeJson({
    required String system,
    required String user,
  }) async {
    sent.add(user);
    return '{"items":['
        '{"type":"task","title":"Preparare slide TNG","date":"2026-10-07","related":"E1"},'
        '{"type":"event","title":"Visita","start":"2026-10-06T15:00","end":"2026-10-06T16:00"}'
        '],"note":null}';
  }
}
