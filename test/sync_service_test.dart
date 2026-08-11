import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('la riconciliazione limita le finestre silenziose di Realtime', () {
    expect(SyncService.periodicInterval, const Duration(minutes: 10));
    expect(SyncService.eventDebounce, lessThan(const Duration(seconds: 1)));
  });

  test('un canale Realtime interrotto viene riaperto', () {
    expect(
      shouldReconnectRealtime(RealtimeSubscribeStatus.channelError),
      isTrue,
    );
    expect(shouldReconnectRealtime(RealtimeSubscribeStatus.closed), isTrue);
    expect(shouldReconnectRealtime(RealtimeSubscribeStatus.timedOut), isTrue);
    expect(
      shouldReconnectRealtime(RealtimeSubscribeStatus.subscribed),
      isFalse,
    );
  });

  test('Realtime resta disconnesso mentre l app è in background', () {
    expect(
      shouldSubscribeRealtime(
        paused: true,
        hasAuthenticatedUser: true,
        hasChannel: false,
      ),
      isFalse,
    );
    expect(
      shouldSubscribeRealtime(
        paused: false,
        hasAuthenticatedUser: true,
        hasChannel: false,
      ),
      isTrue,
    );
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

  test('la notifica auth iniziale non duplica il sync di avvio', () {
    expect(SyncService.shouldSyncForAuthChange('user-a', 'user-a'), isFalse);
    expect(SyncService.shouldSyncForAuthChange(null, 'user-a'), isTrue);
    expect(SyncService.shouldSyncForAuthChange('user-a', 'user-b'), isTrue);
    expect(SyncService.shouldSyncForAuthChange('user-a', null), isFalse);
  });

  test('l aggiornamento dei tentativi non riavvia la coda outbox', () {
    expect(outboxOperationsChanged({}, {'operation-a'}), isTrue);
    expect(outboxOperationsChanged({'operation-a'}, {'operation-a'}), isFalse);
    expect(
      outboxOperationsChanged({'operation-a'}, {'operation-a', 'operation-b'}),
      isTrue,
    );
    expect(outboxOperationsChanged({'operation-a'}, {}), isTrue);
  });

  test('riconosce solo il conflitto univoco delle ricorrenze', () {
    expect(
      isRecurringOccurrenceConflict(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint '
              '"tasks_user_id_series_id_occurrence_key_key"',
          code: '23505',
        ),
      ),
      isTrue,
    );
    expect(
      isRecurringOccurrenceConflict(
        const PostgrestException(message: 'rete', code: '500'),
      ),
      isFalse,
    );
  });
}
