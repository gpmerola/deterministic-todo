import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_fingerprints.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

const _user = '00000000-0000-4000-8000-000000000001';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late SyntheticSyncServer server;
  late AppDatabase a;
  late TaskRepository phone;
  late SyncService sync;
  setUp(() async {
    server = SyntheticSyncServer()..overview = true;
    a = AppDatabase.forTesting(NativeDatabase.memory());
    phone = TaskRepository(a, deviceId: '00000000-0000-4000-8000-000000000010');
    final client = await server.client();
    sync = SyncService(a, client);
    addTearDown(() async {
      await sync.dispose();
      await client.dispose();
      await a.close();
    });
  });

  Future<Task> local(String id) =>
      (a.select(a.tasks)..where((r) => r.id.equals(id))).getSingle();

  test('50 edits cost one bulk read, 50 writes and one receipt', () async {
    for (var i = 0; i < 50; i++) {
      await phone.create('Synthetic $i');
    }
    await sync.sync();
    for (final task in await a.select(a.tasks).get()) {
      await phone.updateDetails(
        task,
        title: '${task.title} *',
        notes: task.notes,
        showDate: task.showDate,
      );
    }
    final requests = server.requests;
    final receipts = server.receiptBatches;
    await sync.sync(pullAll: false);
    expect(server.requests - requests, lessThanOrEqualTo(52));
    expect(server.receiptBatches - receipts, 1);
    expect(await a.select(a.outboxEntries).get(), isEmpty);
    expect(
      server.tables['tasks']!.values.every(
        (row) => (row['title'] as String).endsWith(' *'),
      ),
      isTrue,
    );
  });

  test(
    'a remote write after the bulk read is merged, not overwritten',
    () async {
      final id = await phone.create('Originale', showDate: '2026-09-25');
      await sync.sync();
      await phone.updateDetails(
        await local(id),
        title: 'Titolo telefono',
        notes: null,
        showDate: '2026-09-25',
      );
      var raced = false;
      server.beforeWrite = (table, rowId) async {
        if (raced || rowId != id) return;
        raced = true;
        final row = server.tables['tasks']![id]!;
        server.tables['tasks']![id] = {
          ...row,
          'show_date': '2026-10-01',
          'logical_version': (row['logical_version'] as int) + 5,
          'device_id': '00000000-0000-4000-8000-000000000020',
        };
      };
      await sync.sync(pullAll: false);
      final saved = server.tables['tasks']![id]!;
      expect(saved['title'], 'Titolo telefono');
      expect(saved['show_date'], '2026-10-01');
      expect(await a.select(a.outboxEntries).get(), isEmpty);
    },
  );

  test(
    'a failed bulk receipt keeps writes confirmed for the next cycle',
    () async {
      await phone.create('Uno');
      await phone.create('Due');
      server.failReceipt = true;
      await sync.sync(pullAll: false);
      expect(sync.latest.phase, SyncPhase.error);
      final pending = await a.select(a.outboxEntries).get();
      expect(pending, hasLength(2));
      expect(
        pending.every(
          (e) => (jsonDecode(e.payload) as Map)['confirmed'] == true,
        ),
        isTrue,
      );
      final writes = server.writes;
      server.failReceipt = false;
      await sync.sync(pullAll: false);
      expect(server.writes, writes);
      expect(await a.select(a.outboxEntries).get(), isEmpty);
      expect(server.receipts, hasLength(2));
    },
  );

  test('realtime echoes of known versions are not fetched again', () async {
    final id = await phone.create('Eco');
    await sync.sync();
    final echo = Map<String, dynamic>.from(server.tables['tasks']![id]!);
    final reads = server.inReads;
    await sync.pullRealtimeChangesForTesting(
      'tasks',
      const [],
      records: [echo],
    );
    expect(server.inReads, reads);

    final newer = {
      ...echo,
      'title': 'Dal Web',
      'logical_version': (echo['logical_version'] as int) + 1,
      'device_id': '00000000-0000-4000-8000-000000000020',
    };
    server.tables['tasks']![id] = newer;
    await sync.pullRealtimeChangesForTesting(
      'tasks',
      const [],
      records: [newer],
    );
    expect(server.inReads, reads + 1);
    expect((await local(id)).title, 'Dal Web');

    await sync.pullRealtimeChangesForTesting('tasks', [id]); // No version.
    expect(server.inReads, reads + 2);
  });

  test('a local-only row is reported as an unresolved bucket', () async {
    final id = await phone.create('Solo locale');
    await a.delete(a.outboxEntries).go();
    final source = await local(id);
    final remoteId = '${id.substring(0, 2)}ffffff-0000-4000-8000-000000000000';
    server.tables['tasks']![remoteId] = {
      ...taskToRemote(source, _user),
      'id': remoteId,
    };
    await sync.sync();
    expect(await a.select(a.tasks).get(), hasLength(2));
    final scope = SyncRequestScope(sync.client);
    final bucket = id.substring(0, 2);
    expect(
      await unresolvedTaskBuckets(a, server.taskFingerprints(), [
        bucket,
      ], scope),
      1,
    );
    server.tables['tasks']![id] = taskToRemote(source, _user);
    expect(
      await unresolvedTaskBuckets(a, server.taskFingerprints(), [
        bucket,
      ], scope),
      0,
    );
  });
}
