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
  });
}
