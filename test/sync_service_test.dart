import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('il controllo periodico di sicurezza non usa polling frequente', () {
    expect(SyncService.periodicInterval, const Duration(minutes: 15));
    expect(SyncService.eventDebounce, lessThan(const Duration(seconds: 1)));
  });

  test(
    'più modifiche pendenti della stessa attività producono un solo invio',
    () {
      expect(distinctEntityIds(['task-a', 'task-a', 'task-b', 'task-a']), {
        'task-a',
        'task-b',
      });
    },
  );
}
