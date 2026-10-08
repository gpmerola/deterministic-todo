import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'schema 8 upgrade preserves queued payloads and adds searchable index',
    () async {
      final directory = await Directory.systemTemp.createTemp('todo-outbox-');
      final file = File('${directory.path}/fixture.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              operationId: 'op',
              entityId: 'entity',
              operation: 'upsert',
              payload: '{"synthetic":"pending"}',
              createdAt: 1,
            ),
          );
      await db.close();
      final previous = sqlite.sqlite3.open(file.path);
      previous.execute('DROP INDEX outbox_entity_operation_idx');
      previous.execute('PRAGMA user_version = 8');
      previous.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect(
        (await db.select(db.outboxEntries).getSingle()).payload,
        '{"synthetic":"pending"}',
      );
      final plan = await db
          .customSelect(
            "EXPLAIN QUERY PLAN SELECT operation_id FROM outbox_entries WHERE entity_id = 'entity' AND operation = 'upsert'",
          )
          .get();
      expect(
        plan.map((r) => r.read<String>('detail')).join(),
        contains('USING INDEX outbox_entity_operation_idx'),
      );
      await db.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'ID-only watch handles large descriptions without materializing payloads',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.batch(
        (batch) => batch.insertAll(db.outboxEntries, [
          for (var i = 0; i < 10000; i++)
            OutboxEntriesCompanion.insert(
              operationId: 'op-$i',
              entityId: 'entity-$i',
              operation: 'upsert',
              payload: 'x' * 2048,
              createdAt: i,
            ),
        ]),
      );
      final watch = Stopwatch()..start();
      final ids = await db.watchOutboxOperationIds().first;
      expect(ids, hasLength(10000));
      expect(ids.contains('op-9999'), true);
      // Technical timing only; no hardware performance claim or fragile threshold.
      // ignore: avoid_print
      print(
        'Outbox 10000 IDs / 20 MB synthetic payload: ${watch.elapsedMilliseconds} ms',
      );
      await (db.update(db.outboxEntries)
            ..where((r) => r.operationId.equals('op-1')))
          .write(const OutboxEntriesCompanion(payload: Value('changed')));
      expect(await db.watchOutboxOperationIds().first, ids);
      await (db.delete(
        db.outboxEntries,
      )..where((r) => r.operationId.equals('op-1'))).go();
      expect(await db.watchOutboxOperationIds().first, hasLength(9999));
      await db.close();
    },
  );
}
