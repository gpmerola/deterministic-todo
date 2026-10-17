import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/purge_batch_merge.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_fingerprints.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'support/sync_server.dart';

void main() {
  test(
    'bulk purge is idempotent and preserves an unrelated domain intent with the same UUID',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final client = await SyntheticSyncServer().client();
      final scope = SyncRequestScope(client);
      await TaskRepository(db, deviceId: 'synthetic').create('Synthetic purge');
      final task = await db.select(db.tasks).getSingle();
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              operationId: 'other-domain',
              entityId: task.id,
              operation: 'projects',
              payload: '{}',
              createdAt: 1,
            ),
          );
      final rows = <Map<String, dynamic>>[
        for (var i = 0; i < 1000; i++)
          {
            'entity_type': 'tasks',
            'entity_id':
                '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          },
        {'entity_type': 'tasks', 'entity_id': task.id},
      ];
      await mergePurgeBatch(db, rows, scope);
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(
        (await db.select(db.outboxEntries).getSingle()).operationId,
        'other-domain',
      );
      final revisions = (await db.select(db.activityRevisions).get()).length;
      await mergePurgeBatch(db, rows, scope);
      expect((await db.select(db.activityRevisions).get()).length, revisions);
      expect(
        (await db
                .customSelect(
                  "SELECT count(*) AS n FROM app_settings WHERE key LIKE 'purged:%'",
                )
                .getSingle())
            .read<int>('n'),
        1001,
      );
      await db.close();
      await client.dispose();
    },
  );

  test(
    'one overview replaces unchanged table requests and detects projects, sections and purge',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final server = SyntheticSyncServer()..overview = true;
      final client = await server.client();
      final sync = SyncService(db, client);
      final repo = TaskRepository(
        db,
        deviceId: '00000000-0000-4000-8000-000000000001',
      );
      final project = await repo.createProject('Synthetic project');
      await repo.createProjectSection(project, 'Synthetic section');
      await repo.create('Synthetic task');
      final task = await db.select(db.tasks).getSingle();
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      server.pages = 0;
      server.overviewReads = 0;
      await sync.sync();
      expect(server.pages, 0);
      expect(server.overviewReads, 1);
      expect(server.fingerprintReads, 0);
      for (final table in ['projects', 'project_sections']) {
        final row = server.tables[table]!.values.single;
        row['name'] = 'Remote synthetic';
        row['logical_version'] = (row['logical_version'] as int) + 1;
      }
      server.tables['tasks']!.remove(task.id);
      server.tables['purged_entities']!['00000000-0000-4000-8000-000000000099'] =
          {
            'id': '00000000-0000-4000-8000-000000000099',
            'entity_type': 'tasks',
            'entity_id': task.id,
          };
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      expect(server.pages, 6);
      expect(
        (await db.select(db.projects).getSingle()).name,
        'Remote synthetic',
      );
      expect(
        (await db.select(db.projectSections).getSingle()).name,
        'Remote synthetic',
      );
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(
        (await db.select(db.activityRevisions).get()).any(
          (r) => r.entityId == task.id && r.source == 'sync_purge',
        ),
        isTrue,
      );
      server.pages = 0;
      await sync.sync();
      expect(server.pages, 0);
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );

  test(
    'fingerprint cache survives reopen and invalidates atomically on edits, deletes and rollback',
    () async {
      final dir = await Directory.systemTemp.createTemp('todo-cache-');
      final file = File('${dir.path}/fixture.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      final client = await SyntheticSyncServer().client();
      final scope = SyncRequestScope(client);
      await TaskRepository(db, deviceId: 'synthetic').create('Synthetic');
      final task = await db.select(db.tasks).getSingle();
      final bucket = task.id.substring(0, 2);
      final before = await cachedTaskFingerprints(db, [bucket], scope);
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect(await cachedTaskFingerprints(db, [bucket], scope), before);
      await expectLater(
        db.transaction(() async {
          await db.customUpdate(
            'UPDATE tasks SET logical_version = logical_version + 1',
          );
          expect(
            await cachedTaskFingerprints(db, [bucket], scope),
            isNot(before),
          );
          throw StateError('Synthetic rollback');
        }),
        throwsStateError,
      );
      expect(await cachedTaskFingerprints(db, [bucket], scope), before);
      // Independent SQL path stands for import/restore/remote merge: triggers apply
      // even when the caller does not use TaskRepository or emit Drift streams.
      await db.customUpdate(
        'UPDATE tasks SET logical_version = logical_version + 1',
      );
      final after = await cachedTaskFingerprints(db, [bucket], scope);
      expect(after, isNot(before));
      await db.delete(db.tasks).go();
      expect(await cachedTaskFingerprints(db, [bucket], scope), isNot(after));
      await db.close();
      await client.dispose();
      await dir.delete(recursive: true);
    },
  );

  test(
    'schema 9 upgrade preserves pending intents and installs cache invalidation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'todo-cache-migration-',
      );
      final file = File('${dir.path}/fixture.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      await TaskRepository(
        db,
        deviceId: 'synthetic',
      ).create('Synthetic queued');
      final queued = (await db.select(db.outboxEntries).getSingle()).payload;
      await db.close();
      final previous = sqlite.sqlite3.open(file.path);
      for (final op in ['insert', 'update', 'delete']) {
        previous.execute('DROP TRIGGER tasks_fingerprint_$op');
      }
      previous.execute('PRAGMA user_version = 9');
      previous.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect((await db.select(db.outboxEntries).getSingle()).payload, queued);
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'tasks_fingerprint_%'",
          )
          .get();
      expect(triggers, hasLength(3));
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
