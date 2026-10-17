import 'package:deterministic_todo/services/ai_settings.dart';
import 'package:deterministic_todo/ui/ai_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'salva la chiave solo nell archivio sicuro e la mostra mascherata',
    () async {
      final settings = AiSettings();
      expect((await settings.read()).hasKey, isFalse);
      await settings.save(AiProvider.anthropic, '  sk-ant-secret-1234 ');
      final config = await settings.read();
      expect(config.provider, AiProvider.anthropic);
      expect(config.maskedKey, '…1234');
      expect(await settings.apiKey(), 'sk-ant-secret-1234');
      await settings.clear();
      expect((await settings.read()).hasKey, isFalse);
      expect(
        () => settings.save(AiProvider.deepseek, '  '),
        throwsFormatException,
      );
    },
  );

  test('la verifica legge solo l elenco modelli, senza contenuti', () async {
    final requests = <http.Request>[];
    final settings = AiSettings(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{}',
          request.headers.containsKey('x-api-key') ? 200 : 401,
        );
      }),
    );
    expect(await settings.check(AiProvider.anthropic, 'k'), AiKeyCheck.valid);
    expect(await settings.check(AiProvider.deepseek, 'k'), AiKeyCheck.rejected);
    expect(requests.map((r) => r.url.toString()), [
      'https://api.anthropic.com/v1/models',
      'https://api.deepseek.com/models',
    ]);
    expect(requests.every((r) => r.method == 'GET' && r.body.isEmpty), isTrue);
    expect(requests.first.headers['anthropic-version'], '2023-06-01');
    expect(requests.last.headers['Authorization'], 'Bearer k');

    final down = AiSettings(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await down.check(AiProvider.deepseek, 'k'), AiKeyCheck.unreachable);
    final busy = AiSettings(
      client: MockClient((_) async => http.Response('', 503)),
    );
    expect(await busy.check(AiProvider.deepseek, 'k'), AiKeyCheck.unreachable);
  });

  testWidgets('una chiave rifiutata non viene salvata', (tester) async {
    final settings = AiSettings(
      client: MockClient(
        (request) async => http.Response(
          '',
          request.headers['Authorization'] == 'Bearer good' ? 200 : 401,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsView(settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('ai-key-input')), 'bad');
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ha rifiutato la chiave'), findsOneWidget);
    expect((await settings.read()).hasKey, isFalse);

    await tester.enterText(find.byKey(const ValueKey('ai-key-input')), 'good');
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pumpAndSettle();
    expect(find.text('Chiave …good'), findsNothing);
    expect(find.byKey(const ValueKey('ai-current-key')), findsOneWidget);
    expect(find.textContaining('verificata e salvata'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-confirm-clear')));
    await tester.pumpAndSettle();
    expect((await settings.read()).hasKey, isFalse);
  });
}
