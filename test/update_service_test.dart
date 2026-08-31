import 'package:deterministic_todo/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confronto versioni aggiornamenti', () {
    test('riconosce una patch più recente', () {
      expect(UpdateService.isNewerVersion('1.0.2', '1.0.1'), isTrue);
    });

    test('non propone la stessa versione', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.1'), isFalse);
    });

    test('non propone una versione precedente', () {
      expect(UpdateService.isNewerVersion('1.9.9', '2.0.0'), isFalse);
    });

    test('confronta numericamente e non alfabeticamente', () {
      expect(UpdateService.isNewerVersion('1.10.0', '1.9.0'), isTrue);
    });

    test('ignora il suffisso dev senza trasformare la patch in zero', () {
      expect(UpdateService.isNewerVersion('2.26.7', '2.26.8-dev'), isFalse);
      expect(UpdateService.isNewerVersion('2.26.9', '2.26.8-dev'), isTrue);
    });

    test('confronta la build logica Todo Test con versionCode Android', () {
      expect(
        UpdateService.isNewerRelease(
          candidateVersion: '2.26.8',
          candidateBuild: 130,
          installedVersion: '2.26.8-dev',
          installedBuild: 2131,
          distributionChannel: 'dev',
        ),
        isFalse,
      );
      expect(
        UpdateService.isNewerRelease(
          candidateVersion: '2.26.8',
          candidateBuild: 132,
          installedVersion: '2.26.8-dev',
          installedBuild: 2131,
          distributionChannel: 'dev',
        ),
        isTrue,
      );
    });
  });

  test('il manifest usa un cache-buster diverso a ogni controllo', () {
    final manifest = Uri.parse('https://example.com/manifest.json');
    final first = UpdateService.cacheBustedManifest(
      manifest,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    final second = UpdateService.cacheBustedManifest(
      manifest,
      DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    expect(first.path, manifest.path);
    expect(first.queryParameters['check'], '1000');
    expect(second.queryParameters['check'], '2000');
    expect(second, isNot(first));
  });

  test('Todo Test seleziona soltanto un APK con package dev', () {
    final platforms = {
      'android-arm64-v8a',
      'android-dev-arm64-v8a',
      'android-dev',
    };
    expect(
      UpdateService.platformKeyFor(
        distributionChannel: 'dev',
        abi: 'arm64-v8a',
        available: platforms,
      ),
      'android-dev-arm64-v8a',
    );
    expect(
      UpdateService.platformKeyFor(
        distributionChannel: 'dev',
        abi: 'x86_64',
        available: {'android', 'android-arm64-v8a'},
      ),
      isNull,
    );
  });

  test('Todo Test usa un manifest rolling separato da quello stabile', () {
    expect(
      UpdateService.manifestUriFor('dev').path,
      contains('/releases/download/todo-test-latest/manifest.json'),
    );
    expect(
      UpdateService.manifestUriFor('direct').path,
      contains('/releases/latest/download/manifest.json'),
    );
  });
}
