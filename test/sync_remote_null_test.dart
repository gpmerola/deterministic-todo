import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/remote_batch_merge.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

const _user = '00000000-0000-4000-8000-000000000001';
const _web = '00000000-0000-4000-8000-0000000000aa';

/// A synthetic weekly occurrence, as created on one device and later edited
/// elsewhere: the server clears date, recurrence and occurrence key.
Future<Task> _recurringLocal(AppDatabase db) async {
  await TaskRepository(db, deviceId: _web).create(
    'Synthetic weekly',
    showDate: '2026-10-08',
    recurrence: 'calendar:week:1',
  );
  await db.delete(db.outboxEntries).go();
  return db.select(db.tasks).getSingle();
}

Map<String, dynamic> _cleared(Task task, {required int version}) => {
  ...taskToRemote(task, _user),
  'status': 'inbox',
  'show_date': null,
  'recurrence': null,
  'occurrence_key': null,
  'logical_version': version,
  'device_id': _web,
};

void main() {
  test('a newer remote row clears nullable columns of the local row', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = await SyntheticSyncServer().client();
    final local = await _recurringLocal(db);
    expect(local.recurrence, 'calendar:week:1');

    await mergeRemoteBatch(db, 'tasks', [
      _cleared(local, version: local.logicalVersion + 1),
    ], SyncRequestScope(client));

    final merged = await db.select(db.tasks).getSingle();
    expect(merged.status, 'inbox');
    expect(merged.showDate, isNull);
    expect(merged.recurrence, isNull);
    expect(merged.occurrenceKey, isNull);
    await db.close();
  });

  test(
    'an equal stamp with different content is repaired once, then is a no-op',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final client = await SyntheticSyncServer().client();
      final scope = SyncRequestScope(client);
      final local = await _recurringLocal(db);
      await (db.update(db.tasks)..where((r) => r.id.equals(local.id))).write(
        TasksCompanion(
          logicalVersion: const Value(1432),
          deviceId: const Value(_web),
        ),
      );
      final remote = _cleared(local, version: 1432);

      await mergeRemoteBatch(db, 'tasks', [remote], scope);
      final repaired = await db.select(db.tasks).getSingle();
      expect(repaired.showDate, isNull);
      expect(repaired.recurrence, isNull);
      final revisions = (await db.select(db.activityRevisions).get()).length;

      await mergeRemoteBatch(db, 'tasks', [remote], scope);
      expect((await db.select(db.activityRevisions).get()).length, revisions);
      await db.close();
    },
  );

  test('an older remote row never overwrites the local row', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = await SyntheticSyncServer().client();
    final local = await _recurringLocal(db);
    await (db.update(db.tasks)..where((r) => r.id.equals(local.id))).write(
      const TasksCompanion(logicalVersion: Value(10)),
    );

    await mergeRemoteBatch(db, 'tasks', [
      _cleared(local, version: 9),
    ], SyncRequestScope(client));

    final kept = await db.select(db.tasks).getSingle();
    expect(kept.showDate, '2026-10-08');
    expect(kept.recurrence, 'calendar:week:1');
    await db.close();
  });

  test('a remote project clears its parent and color', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = await SyntheticSyncServer().client();
    const id = '00000000-0000-4000-8000-0000000000p1';
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: 'Synthetic child',
            parentId: const Value('00000000-0000-4000-8000-0000000000p0'),
            color: const Value('red'),
            position: 1,
            deviceId: _web,
            logicalVersion: const Value(3),
          ),
        );
    await db.delete(db.outboxEntries).go();

    await mergeRemoteBatch(db, 'projects', [
      {
        'id': id,
        'user_id': _user,
        'name': 'Synthetic child',
        'color': null,
        'parent_id': null,
        'position': 1,
        'is_favorite': false,
        'is_archived': false,
        'external_source': null,
        'external_id': null,
        'logical_version': 4,
        'device_id': _web,
      },
    ], SyncRequestScope(client));

    final project = await db.select(db.projects).getSingle();
    expect(project.parentId, isNull);
    expect(project.color, isNull);
    await db.close();
  });

  test(
    'an upgraded database repairs equal-version divergence with one full pull',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final local = await _recurringLocal(db);
      // A fresh database never needs the repair; an upgraded one has no marker.
      expect(await needsRemoteNullRepair(db), isFalse);
      await (db.delete(
        db.appSettings,
      )..where((r) => r.key.equals(remoteNullRepairKey))).go();

      final server = SyntheticSyncServer()..fingerprints = true;
      server.tables['tasks']![local.id] = _cleared(
        local,
        version: local.logicalVersion,
      );
      final client = await server.client();
      final sync = SyncService(db, client);

      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      final repaired = await db.select(db.tasks).getSingle();
      expect(repaired.status, 'inbox');
      expect(repaired.showDate, isNull);
      expect(repaired.recurrence, isNull);
      expect(repaired.occurrenceKey, isNull);
      expect(await needsRemoteNullRepair(db), isFalse);
      expect(server.fingerprintReads, 0);

      // Afterwards matching fingerprints skip the task download again.
      final pages = server.pages;
      await sync.sync();
      expect(server.fingerprintReads, 1);
      expect(server.pages - pages, 3); // Projects, sections, purge ledger.
      await sync.dispose();
      await db.close();
    },
  );
}
