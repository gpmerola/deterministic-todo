import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

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

  test(
    'full pull exceeds server cap and 1000 rows without omissions',
    () async {
      await phone.create('Synthetic');
      final source = await a.select(a.tasks).getSingle();
      await a.delete(a.outboxEntries).go();
      await a.delete(a.tasks).go();
      server.pageCap = 73;
      for (var i = 0; i < 1501; i++) {
        final id = '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
        server.tables['tasks']![id] = {
          ...taskToRemote(source, '00000000-0000-4000-8000-000000000001'),
          'id': id,
        };
      }
      await syncA.sync();
      expect(syncA.latest.phase, SyncPhase.current);
      expect(await a.select(a.tasks).get(), hasLength(1501));
      expect(server.pages, greaterThan(20));
    },
  );

  test('two clients preserve concurrent title and date changes', () async {
    await phone.create(
      'Originale',
      showDate: '2026-09-11',
      status: TaskStatus.available,
    );
    await syncA.sync();
    await syncB.sync();
    final pa = await a.select(a.tasks).getSingle();
    final pb = await b.select(b.tasks).getSingle();
    await phone.updateDetails(
      pa,
      title: 'Titolo telefono',
      notes: pa.notes,
      showDate: pa.showDate,
    );
    await web.updateDetails(
      pb,
      title: pb.title,
      notes: pb.notes,
      showDate: '2026-09-20',
      status: TaskStatus.scheduled,
    );
    await syncA.sync();
    await syncB.sync();
    await syncA.sync();
    final saved = await a.select(a.tasks).getSingle();
    expect(saved.title, 'Titolo telefono');
    expect(saved.showDate, '2026-09-20');
    expect(saved.toJson(), (await b.select(b.tasks).getSingle()).toJson());
  });

  test('one uncertain task does not block another or remote pull', () async {
    final blockedId = await phone.create('Conflitto sintetico');
    await syncA.sync();
    final task = await a.select(a.tasks).getSingle();
    await phone.move(task, TaskStatus.waiting);
    server.loseResponse.add(blockedId);
    await syncA.sync();
    server.loseResponse.clear();
    server.tables['tasks']![blockedId] = {
      ...server.tables['tasks']![blockedId]!,
      'title': 'Successiva remota',
      'logical_version': 90,
    };
    final goodId = await phone.create('Indipendente');
    await syncA.sync();
    expect(server.tables['tasks']![goodId]?['title'], 'Indipendente');
    final pending = await a.select(a.outboxEntries).get();
    expect(pending, hasLength(1));
    expect(pending.single.entityId, blockedId);
    expect(pending.single.lastError, 'intent_conflict');
    expect(syncA.latest.phase, SyncPhase.error);
    expect(
      (await a.select(a.activityRevisions).get()).any(
        (r) => r.source == 'sync_conflict',
      ),
      isTrue,
    );
  });

  test(
    'projects and sections preserve distinct concurrent edits using CAS',
    () async {
      final projectId = await phone.createProject('Progetto');
      await phone.createProjectSection(projectId, 'Sezione');
      await syncA.sync();
      await syncB.sync();
      expect(syncA.latest.phase, SyncPhase.current);
      final pa = await a.select(a.projects).getSingle();
      final pb = await b.select(b.projects).getSingle();
      await phone.updateProject(pa, name: 'Nome telefono');
      await web.updateProject(pb, position: 8192);
      server.beforeWrite = (table, _) async {
        if (table != 'projects') return;
        server.beforeWrite = null;
        await syncB.sync();
      };
      await syncA.sync();
      await syncB.sync();
      final saved = await a.select(a.projects).getSingle();
      expect(saved.name, 'Nome telefono');
      expect(saved.position, 8192);
      final sa = await a.select(a.projectSections).getSingle();
      final sb = await b.select(b.projectSections).getSingle();
      await phone.updateProjectSection(sa, name: 'Sezione telefono');
      await web.updateProjectSection(sb, position: 4096);
      await syncA.sync();
      await syncB.sync();
      await syncA.sync();
      expect(
        (await a.select(a.projectSections).getSingle()).name,
        'Sezione telefono',
      );
      expect((await a.select(a.projectSections).getSingle()).position, 4096);
      expect(await a.select(a.outboxEntries).get(), isEmpty);
      expect(
        server.receipts.values.every((r) => r['operation'] == 'upsert'),
        isTrue,
      );
      expect(jsonEncode(server.receipts), isNot(contains('Nome telefono')));
    },
  );

  test(
    'project response loss keeps local intent until explicitly resolved',
    () async {
      final id = await phone.createProject('Base');
      await syncA.sync();
      await phone.updateProject(
        await a.select(a.projects).getSingle(),
        name: 'Mio nome',
      );
      server.loseResponse.add(id);
      await syncA.sync();
      server.loseResponse.clear();
      server.tables['projects']![id] = {
        ...server.tables['projects']![id]!,
        'name': 'Nome successivo',
        'logical_version': 99,
      };
      await syncA.sync();
      expect(
        (await a.select(a.outboxEntries).getSingle()).lastError,
        'intent_conflict',
      );
      await phone.restoreProjectRevision(
        'projects',
        server.tables['projects']![id]!,
      );
      await syncA.sync();
      expect(await a.select(a.outboxEntries).get(), isEmpty);
      expect((await a.select(a.projects).getSingle()).name, 'Nome successivo');
    },
  );

  test(
    'failed receipt never replays an accepted project over a later change',
    () async {
      final id = await phone.createProject('Base');
      await syncA.sync();
      await phone.updateProject(
        await a.select(a.projects).getSingle(),
        name: 'Primo',
      );
      server.failReceipt = true;
      await syncA.sync();
      server.failReceipt = false;
      final writes = server.writes;
      server.tables['projects']![id] = {
        ...server.tables['projects']![id]!,
        'name': 'Secondo',
        'logical_version': 99,
      };
      await syncA.sync();
      expect(server.writes, writes);
      expect((await a.select(a.projects).getSingle()).name, 'Secondo');
      expect(await a.select(a.outboxEntries).get(), isEmpty);
    },
  );

  test('purge ledger removes only explicitly purged UUIDs', () async {
    final id = await phone.create('Da eliminare');
    final keep = await phone.create('Da conservare');
    await syncA.sync();
    await syncB.sync();
    server.tables['tasks']!.remove(id);
    server.tables['purged_entities']!['00000000-0000-4000-8000-000000000099'] =
        {
          'id': '00000000-0000-4000-8000-000000000099',
          'entity_type': 'tasks',
          'entity_id': id,
        };
    await syncB.sync();
    expect((await b.select(b.tasks).get()).map((e) => e.id), [keep]);
    expect(
      (await b.select(b.activityRevisions).get()).any(
        (r) => r.entityId == id && r.source == 'sync_purge',
      ),
      isTrue,
    );
  });

  test(
    'a delayed remote row cannot resurrect an already observed purge',
    () async {
      final id = await phone.create('Eliminazione sintetica');
      await syncA.sync();
      final stale = Map<String, dynamic>.from(server.tables['tasks']![id]!);
      final original = await a.select(a.tasks).getSingle();
      server.tables['tasks']!.remove(id);
      server.tables['purged_entities']!['00000000-0000-4000-8000-000000009999'] =
          {
            'id': '00000000-0000-4000-8000-000000009999',
            'entity_type': 'tasks',
            'entity_id': id,
          };
      await syncA.sync();
      // Simulate an older snapshot arriving after the ledger has been observed.
      server.tables['purged_entities']!.clear();
      server.tables['tasks']![id] = stale;
      await syncA.sync();
      expect(await a.select(a.tasks).get(), isEmpty);
      await expectLater(phone.restoreRevision(original), throwsFormatException);
      expect(await a.select(a.outboxEntries).get(), isEmpty);
    },
  );

  test('project intents rollback together with their domain rows', () async {
    await expectLater(
      a.transaction(() async {
        await phone.createProject('Rollback');
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await a.select(a.projects).get(), isEmpty);
    expect(await a.select(a.outboxEntries).get(), isEmpty);
  });
}
