import 'package:deterministic_todo/data/diagnostic_queries.dart';
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SQL counts preserve semantics without returning content', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepository(db, deviceId: 'synthetic');
    await repo.create('Synthetic');
    final counts = await diagnosticCounts(db);
    expect(counts.tasks, 1);
    expect(counts.pending, 1);
    expect(counts.projects, 0);
  });

  test(
    'group before paging; latest operation wins; payload stays in SQL',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.batch(
        (b) => b.insertAll(db.outboxEntries, [
          for (var entity = 0; entity < 120; entity++)
            for (var revision = 0; revision < 3; revision++)
              OutboxEntriesCompanion.insert(
                operationId: '$entity-$revision',
                entityId: 'task-$entity',
                operation: revision == 2 ? 'delete' : 'upsert',
                payload: 'synthetic payload ${'x' * 1000}',
                createdAt: entity * 10 + revision,
                lastError: Value(revision == 2 ? 'server_rejected' : null),
              ),
        ]),
      );
      final first = await watchSyncIssues(db, offset: 0).first;
      final second = await watchSyncIssues(db, offset: 50).first;
      final third = await watchSyncIssues(db, offset: 100).first;
      expect(first, hasLength(51));
      expect(second, hasLength(51));
      expect(third, hasLength(20));
      final visible = [...first.take(50), ...second.take(50), ...third];
      expect(
        visible.map((r) => r.read<String>('entity_id')).toSet(),
        hasLength(120),
      );
      expect(
        visible.every((r) => r.read<String>('last_error') == 'server_rejected'),
        isTrue,
      );
      expect(first.first.data.containsKey('payload'), isFalse);
      expect(first.first.data.keys.toSet(), {
        'entity_id',
        'last_error',
        'kind',
        'entity_label',
      });
    },
  );

  test(
    'same timestamp tie and same id in different domains remain distinct',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final operation in ['upsert', 'delete', 'projects']) {
        await db
            .into(db.outboxEntries)
            .insert(
              OutboxEntriesCompanion.insert(
                operationId: operation,
                entityId: 'same',
                operation: operation,
                payload: '{}',
                createdAt: 1,
                lastError: Value(operation),
              ),
            );
      }
      final rows = await watchSyncIssues(db, offset: 0).first;
      expect(rows, hasLength(2));
      expect(rows.first.read<String>('last_error'), 'delete');
      expect(rows.last.read<String>('kind'), 'projects');
    },
  );
}
