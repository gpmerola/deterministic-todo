import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sync_server.dart';

const _user = '00000000-0000-4000-8000-000000000001';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late SyntheticSyncServer server;
  late AppDatabase a, b;
  late TaskRepository phone, web;
  late SyncService syncA, syncB;
  setUp(() async {
    server = SyntheticSyncServer();
    a = AppDatabase.forTesting(NativeDatabase.memory());
    b = AppDatabase.forTesting(NativeDatabase.memory());
    phone = TaskRepository(a, deviceId: '00000000-0000-4000-8000-000000000010');
    web = TaskRepository(b, deviceId: '00000000-0000-4000-8000-000000000020');
    final ca = await server.client();
    final cb = await server.client();
    syncA = SyncService(a, ca);
    syncB = SyncService(b, cb);
    addTearDown(() async {
      await syncA.dispose();
      await syncB.dispose();
      await ca.dispose();
      await cb.dispose();
      await a.close();
      await b.close();
    });
  });

  Future<List<OutboxEntry>> outbox(String id) =>
      (a.select(a.outboxEntries)..where((r) => r.entityId.equals(id))).get();

  /// Synthetic rows present only on the server, as written by another client.
  Future<List<String>> seedRemote(int count) async {
    await phone.create('Synthetic');
    final source = await a.select(a.tasks).getSingle();
    await a.delete(a.outboxEntries).go();
    await a.delete(a.tasks).go();
    final ids = [
      for (var i = 0; i < count; i++)
        '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
    ];
    for (final id in ids) {
      server.tables['tasks']![id] = {...taskToRemote(source, _user), 'id': id};
    }
    return ids;
  }

  test(
    'a row rejected by the server does not block other uploads or the pull',
    () async {
      final remoteId = await web.create('Remota');
      await syncB.sync();
      final rejectedId = await phone.create('Rifiutata');
      final validId = await phone.create('Valida');
      server.rejectWrite[rejectedId] = '23514';

      await syncA.sync();

      expect(server.tables['tasks']!.containsKey(validId), isTrue);
      expect(server.tables['tasks']!.containsKey(rejectedId), isFalse);
      expect(
        (await (a.select(
          a.tasks,
        )..where((r) => r.id.equals(remoteId))).getSingleOrNull())?.title,
        'Remota',
      );
      expect(await outbox(validId), isEmpty);
      expect((await outbox(rejectedId)).map((e) => e.lastError).toSet(), {
        'server_rejected',
      });
      expect(syncA.latest.phase, SyncPhase.error);
      expect(syncA.latest.error, contains('Rifiutati dal server: 1'));

      server.rejectWrite.clear();
      await syncA.sync();
      expect(syncA.latest.phase, SyncPhase.current);
      expect(await a.select(a.outboxEntries).get(), isEmpty);
      expect(server.tables['tasks']!.containsKey(rejectedId), isTrue);
    },
  );

  test('transport failures after a rejection keep its marker', () async {
    final rejectedId = await phone.create('Rifiutata');
    final otherId = await phone.create('Altra');
    server.rejectWrite[rejectedId] = '23502';
    server.failReceipt = true;

    await syncA.sync();

    expect(syncA.latest.phase, SyncPhase.error);
    expect((await outbox(rejectedId)).single.lastError, 'server_rejected');
    expect((await outbox(otherId)).single.lastError, isNot('server_rejected'));
  });

  test('account-wide server errors still stop the cycle', () async {
    final id = await phone.create('Qualsiasi');
    server.rejectWrite[id] = '42501';
    await syncA.sync();
    expect(syncA.latest.phase, SyncPhase.error);
    expect(syncA.latest.error, 'Supabase 42501');
    expect((await outbox(id)).single.lastError, 'Supabase 42501');
  });

  test('isEntityRejection covers only row data and integrity classes', () {
    PostgrestException error(String? code) =>
        PostgrestException(message: 'synthetic', code: code);
    expect(isEntityRejection(error('23514')), isTrue);
    expect(isEntityRejection(error('22P02')), isTrue);
    expect(isEntityRejection(error('42501')), isFalse);
    expect(isEntityRejection(error('P0001')), isFalse);
    expect(isEntityRejection(error('PGRST301')), isFalse);
    expect(isEntityRejection(error(null)), isFalse);
  });

  test(
    'a fresh check after subscription does not join an older snapshot',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      server.beforeRead = (table) async {
        // The task scan of the first cycle has already completed here.
        if (table == 'purged_entities' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final first = syncA.sync();
      await entered.future;
      final lateId = await web.create('Dopo lo snapshot');
      await syncB.sync(pullAll: false);
      final fresh = syncA.sync(freshSnapshot: true);
      final joined = syncA.sync();
      release.complete();
      await Future.wait([first, fresh, joined]);
      expect(
        await (a.select(
          a.tasks,
        )..where((r) => r.id.equals(lateId))).getSingleOrNull(),
        isNotNull,
      );
      expect(syncA.latest.phase, SyncPhase.current);
    },
  );

  test('realtime bursts are fetched in bounded ID batches', () async {
    final ids = await seedRemote(250);
    await syncA.pullRealtimeChangesForTesting('tasks', ids);
    expect(await a.select(a.tasks).get(), hasLength(250));
    expect(server.inReads, 3);
  });

  test(
    'a failed realtime fetch falls back to a full check instead of dropping it',
    () async {
      final ids = await seedRemote(5);
      server.maxInIds = 0;
      final current = syncA.snapshots.firstWhere(
        (s) => s.phase == SyncPhase.current,
      );
      await syncA.pullRealtimeChangesForTesting('tasks', ids);
      await current.timeout(const Duration(seconds: 5));
      expect(await a.select(a.tasks).get(), hasLength(5));
    },
  );
}
