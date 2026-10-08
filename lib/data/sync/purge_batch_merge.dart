import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';
import 'sync_request_scope.dart';

Future<void> mergePurgeBatch(
  AppDatabase db,
  List<Map<String, dynamic>> rows,
  SyncRequestScope scope,
) async {
  final timer = Stopwatch()..start();
  try {
    await db.withRevisionSource('sync_purge', () async {
      scope.check();
      final groups = <String, Set<String>>{};
      for (final row in rows) {
        final table = row['entity_type'] as String;
        if (!const {'tasks', 'projects', 'project_sections'}.contains(table)) {
          throw const FormatException('Invalid purge type');
        }
        groups.putIfAbsent(table, () => {}).add(row['entity_id'] as String);
      }
      await db.batch(
        (b) => b.insertAll(db.appSettings, [
          for (final group in groups.entries)
            for (final id in group.value)
              AppSettingsCompanion.insert(
                key: 'purged:${group.key}:$id',
                value: '1',
              ),
        ], mode: InsertMode.insertOrIgnore),
      );
      for (final group in groups.entries) {
        final ids = Variable(jsonEncode(group.value.toList()));
        await db.customUpdate(
          'DELETE FROM "${group.key}" WHERE id IN (SELECT value FROM json_each(?))',
          variables: [ids],
          updates: {db.tasks, db.projects, db.projectSections},
        );
        await db.customUpdate(
          'DELETE FROM outbox_entries WHERE entity_id IN (SELECT value FROM json_each(?)) AND '
          "${group.key == 'tasks' ? "operation NOT IN ('projects', 'project_sections')" : 'operation = ?'}",
          variables: [ids, if (group.key != 'tasks') Variable(group.key)],
          updates: {db.outboxEntries},
        );
      }
      scope.check();
    });
  } finally {
    scope.purgeMs += timer.elapsedMilliseconds;
  }
}
