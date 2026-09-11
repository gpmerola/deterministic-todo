import 'dart:async';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

class _Reads extends QueryInterceptor {
  int count = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  test(
    'compact check skips 20000 unchanged rows and catches delayed writes and missing local rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'todo-fingerprint-fixture-',
      );
      final db = AppDatabase.forTesting(
        NativeDatabase.createInBackground(File('${dir.path}/db')),
      );
      final repo = TaskRepository(
        db,
        deviceId: '00000000-0000-4000-8000-000000000001',
      );
      await repo.create('Synthetic fingerprint');
      final source = await db.select(db.tasks).getSingle();
      await db.delete(db.outboxEntries).go();
      await db.delete(db.tasks).go();
      final server = SyntheticSyncServer()..fingerprints = true;
      for (var i = 0; i < 20000; i++) {
        final prefix = (i % 256).toRadixString(16).padLeft(2, '0');
        final id =
            '${prefix}000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
        server.tables['tasks']![id] = {
          ...taskToRemote(source, '00000000-0000-4000-8000-000000000001'),
          'id': id,
          'logical_version': 100,
        };
      }
      await db.batch(
        (b) => b.insertAll(
          db.tasks,
          server.tables['tasks']!.values.map(taskFromRemote),
        ),
      );
      final client = await server.client();
      final sync = SyncService(db, client);
      final watch = Stopwatch()..start();
      await sync.sync();
      watch.stop();
      expect(sync.latest.phase, SyncPhase.current);
      expect(
        server.pages,
        3,
      ); // Only projects, sections, purge ledger; no tasks.
      expect(server.fingerprintReads, 1);
      // ignore: avoid_print
      print(
        'fingerprint_20000: ${watch.elapsedMilliseconds} ms, zero task downloads',
      );

      // A delayed offline writer has a counter BELOW the already observed 100.
      const lateId = 'ff000000-0000-4000-8000-999999999999';
      server.tables['tasks']![lateId] = {
        ...server.tables['tasks']!.values.first,
        'id': lateId,
        'logical_version': 1,
      };
      final removedId = server.tables['tasks']!.keys.first;
      await (db.delete(db.tasks)..where((t) => t.id.equals(removedId))).go();
      final deletedId = server.tables['tasks']!.keys.skip(1).first;
      server.tables['tasks']![deletedId] = {
        ...server.tables['tasks']![deletedId]!,
        'logical_version': 101,
        'deleted_at': 123,
      };
      server.pages = 0;
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      expect(
        server.pages,
        9,
      ); // Three changed buckets, one data + one empty page each.
      expect(
        (await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(lateId))).getSingle()).logicalVersion,
        1,
      );
      expect(
        await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(removedId))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        (await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(deletedId))).getSingle()).deletedAt,
        123,
      );
      server.pages = 0;
      await sync.sync();
      expect(server.pages, 3);
      await sync.dispose();
      await client.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    '1500 unchanged rows use page-sized SQLite work and create no revisions',
    () async {
      final dir = await Directory.systemTemp.createTemp('todo-pull-fixture-');
      final reads = _Reads();
      final db = AppDatabase.forTesting(
        NativeDatabase.createInBackground(
          File('${dir.path}/db'),
        ).interceptWith(reads),
      );
      final repo = TaskRepository(db, deviceId: 'synthetic');
      await repo.create('Synthetic');
      final source = await db.select(db.tasks).getSingle();
      await db.delete(db.outboxEntries).go();
      await db.delete(db.tasks).go();
      final server = SyntheticSyncServer();
      for (var i = 0; i < 1500; i++) {
        final id = 'fixture-$i';
        server.tables['tasks']![id] = {
          ...taskToRemote(source, '00000000-0000-4000-8000-000000000001'),
          'id': id,
        };
      }
      final client = await server.client();
      final sync = SyncService(db, client);
      await sync.sync();
      final historyBefore =
          (await db.select(db.activityRevisions).get()).length;
      reads.count = 0;
      final watch = Stopwatch()..start();
      await sync.sync();
      final queries = reads.count;
      expect(sync.latest.phase, SyncPhase.current);
      expect(
        queries,
        lessThan(100),
      ); // Previous per-row implementation exceeded 9000.
      expect(
        (await db.select(db.activityRevisions).get()).length,
        historyBefore,
      );
      expect(await db.select(db.tasks).get(), hasLength(1500));
      // ignore: avoid_print
      print(
        'unchanged_1500: ${watch.elapsedMilliseconds} ms, $queries SQLite reads',
      );
      await sync.dispose();
      await client.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'overlapping full checks join one cycle instead of repeating the scan',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final server = SyntheticSyncServer();
      final client = await server.client();
      final sync = SyncService(db, client);
      final entered = Completer<void>(), release = Completer<void>();
      server.beforeRead = (table) async {
        if (table == 'projects' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final first = sync.sync();
      await entered.future;
      final joined = [sync.sync(), sync.sync(), sync.sync()];
      release.complete();
      await first;
      await Future.wait(joined);
      expect(
        server.pages,
        4,
      ); // Empty projects, sections, tasks and purge ledger, once.
      expect(sync.latest.phase, SyncPhase.current);
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );

  test(
    'new local work during a full scan still receives a trailing upload',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final server = SyntheticSyncServer();
      final client = await server.client();
      final sync = SyncService(db, client);
      final entered = Completer<void>(), release = Completer<void>();
      server.beforeRead = (table) async {
        if (table == 'tasks' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final first = sync.sync();
      await entered.future;
      await TaskRepository(
        db,
        deviceId: 'synthetic',
      ).create('New synthetic intent');
      final trailing = sync.sync(pullAll: false);
      release.complete();
      await first;
      await trailing;
      expect(server.writes, 1);
      expect(await db.select(db.outboxEntries).get(), isEmpty);
      expect(sync.latest.phase, SyncPhase.current);
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );
}
