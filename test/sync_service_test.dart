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

  test('il retry di rete cresce ma resta limitato', () {
    expect(syncRetryDelay(0), const Duration(seconds: 2));
    expect(syncRetryDelay(1), const Duration(seconds: 10));
    expect(syncRetryDelay(2), const Duration(seconds: 30));
    expect(syncRetryDelay(20), const Duration(minutes: 2));
  });
}
