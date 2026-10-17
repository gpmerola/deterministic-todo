import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/remote_batch_merge.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_fingerprints.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

const _user = '00000000-0000-4000-8000-000000000001';

/// Shared with tools/sql-tests/task_fingerprints_v2.mjs (Postgres side).
final _fixture =
    jsonDecode(
          File('test/fixtures/task_fingerprint_v2.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
List<Map<String, dynamic>> get _rows => [
  for (final row in _fixture['rows'] as List)
    {...Map<String, dynamic>.from(row as Map), 'user_id': _user},
];
Map<String, String> get _expected => {
  for (final e in _fixture['expected'] as List)
    (e as Map)['bucket'] as String: e['fingerprint'] as String,
};

Future<AppDatabase> _localCopy() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.batch(
    (b) => b.insertAll(db.tasks, [
      for (final row in _rows) taskFromRemote(row).toCompanion(false),
    ]),
  );
  return db;
}

Future<SyntheticSyncServer> _server({bool content = true}) async {
  final server = SyntheticSyncServer()
    ..fingerprints = true
    ..overview = true
    ..contentFingerprints = content;
  for (final row in _rows) {
    server.tables['tasks']![row['id'] as String] = row;
  }
  return server;
}

void main() {
  test(
    'Dart reference and SQLite sign the shared fixture like Postgres',
    () async {
      final signatures = <String, StringBuffer>{};
      for (final row
          in _rows..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'))) {
        signatures
            .putIfAbsent('${row['id']}'.substring(0, 2), StringBuffer.new)
            .write(taskRowSignature(row, taskFingerprintV2));
      }
      expect({
        for (final e in signatures.entries)
          e.key: sha256.convert(utf8.encode('${e.value}')).toString(),
      }, _expected);

      final db = await _localCopy();
      final scope = SyncRequestScope(await SyntheticSyncServer().client());
      expect(
        await cachedTaskFingerprints(db, ['a1', 'f2'], scope, version: 2),
        _expected,
      );
      await db.close();
    },
  );

  test('v1 and v2 digests share one cache slot without mixing', () async {
    final db = await _localCopy();
    final scope = SyncRequestScope(await SyntheticSyncServer().client());
    final v1 = await cachedTaskFingerprints(db, ['f2'], scope);
    final v2 = await cachedTaskFingerprints(db, ['f2'], scope, version: 2);
    expect(v2['f2'], _expected['f2']);
    expect(v1['f2'], isNot(v2['f2']));
    final slot = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals('sync_fp:v1:tasks:f2'))).getSingle();
    expect(slot.value, 'v2:${_expected['f2']}');
    expect(await cachedTaskFingerprints(db, ['f2'], scope), v1);
    await db.close();
  });

  test('null, empty and separator-only content never collide', () {
    final base = _rows.first;
    String sig(Map<String, dynamic> change) =>
        taskRowSignature({...base, ...change}, taskFingerprintV2);
    expect(sig({'notes': null}), isNot(sig({'notes': ''})));
    expect(sig({'notes': '-'}), isNot(sig({'notes': null})));
    expect(
      sig({'title': 'a,1#b', 'notes': null}),
      isNot(sig({'title': 'a', 'notes': 'b'})),
    );
  });

  test(
    'regression «hinge»: equal-version content divergence is pulled and repaired',
    () async {
      final db = await _localCopy();
      final hinge = _rows.last;
      // The local copy kept a date and recurrence the server cleared, at the
      // same version and device: v1 stamps cannot see this.
      await (db.update(db.tasks)..where((r) => r.id.equals(hinge['id']))).write(
        const TasksCompanion(
          showDate: Value('2026-10-08'),
          recurrence: Value('calendar:week:1'),
          status: Value('scheduled'),
        ),
      );
      final server = await _server();
      final sync = SyncService(db, await server.client());

      await sync.sync();
      final repaired = await (db.select(
        db.tasks,
      )..where((r) => r.id.equals(hinge['id']))).getSingle();
      expect(repaired.showDate, isNull);
      expect(repaired.recurrence, isNull);
      expect(repaired.status, 'inbox');
      expect(sync.latest.alignment?.aligned, isTrue);
      expect(sync.latest.alignment?.contentChecked, isTrue);

      // Converged: the next cycle downloads no task page.
      final pages = server.pages;
      await sync.sync();
      expect(server.pages - pages, 0); // The overview matches every table.
      await sync.dispose();
      await db.close();
    },
  );

  test(
    'a v1-only server is used after one missing v2 request per client',
    () async {
      final db = await _localCopy();
      final server = await _server(content: false);
      final sync = SyncService(db, await server.client());
      await sync.sync();
      final requests = server.requests;
      await sync.sync();
      // Second cycle: only the v1 overview, no repeated v2 attempt.
      expect(server.requests - requests, 1);
      expect(sync.latest.alignment?.contentChecked, isFalse);
      expect(sync.latest.alignment?.aligned, isTrue);
      await sync.dispose();
      await db.close();
    },
  );

  test(
    'a local-only row is reported and survives an explicit complete repair',
    () async {
      final db = await _localCopy();
      final server = await _server();
      server.tables['tasks']!.remove(_rows.first['id']);
      final sync = SyncService(db, await server.client());

      await sync.sync();
      expect(sync.latest.alignment?.divergedBuckets, 1);

      await sync.repairAlignment();
      expect(await needsRemoteNullRepair(db), isFalse);
      expect(sync.latest.alignment?.repaired, isTrue);
      expect(sync.latest.alignment?.divergedBuckets, 1);
      // Nothing is deleted or uploaded implicitly.
      expect(await db.select(db.tasks).get(), hasLength(_rows.length));
      expect(await db.select(db.outboxEntries).get(), isEmpty);
      await sync.dispose();
      await db.close();
    },
  );

  test('control: v1 stamps alone cannot see the «hinge» divergence', () async {
    final db = await _localCopy();
    final hinge = _rows.last;
    await (db.update(db.tasks)..where((r) => r.id.equals(hinge['id']))).write(
      const TasksCompanion(showDate: Value('2026-10-08')),
    );
    final sync = SyncService(
      db,
      await (await _server(content: false)).client(),
    );
    await sync.sync();
    final kept = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(hinge['id']))).getSingle();
    expect(kept.showDate, '2026-10-08');
    await sync.dispose();
    await db.close();
  });
}
