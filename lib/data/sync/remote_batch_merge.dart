import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/task.dart' as domain;
import '../local/database.dart';
import 'project_sync_writer.dart';
import 'sync_request_scope.dart';
import 'task_sync_writer.dart';

/// One SQLite transaction and a bounded set of queries per page, not per row.
/// Re-read versions/intents inside the transaction so local edits always win
/// while pending; no pre-network local snapshot is used for the write decision.
Future<Set<String>> mergeRemoteBatch(
  AppDatabase db,
  String table,
  List<Map<String, dynamic>> rows,
  SyncRequestScope scope,
) async {
  if (rows.isEmpty) return {};
  if (!const {'tasks', 'projects', 'project_sections'}.contains(table)) {
    throw ArgumentError('Invalid sync table');
  }
  return db.withRevisionSource('sync_pull', () async {
    scope.check();
    final ids = rows.map((r) => r['id'] as String).toList();
    final encodedIds = Variable(jsonEncode(ids));
    final versions = await db
        .customSelect(
          'SELECT id, logical_version, device_id FROM "$table" '
          'WHERE id IN (SELECT value FROM json_each(?))',
          variables: [encodedIds],
        )
        .get();
    final local = {for (final row in versions) row.read<String>('id'): row};
    final pending = await db
        .customSelect(
          'SELECT entity_id FROM outbox_entries '
          'WHERE entity_id IN (SELECT value FROM json_each(?)) '
          "AND ${table == 'tasks' ? "operation NOT IN ('projects', 'project_sections')" : 'operation = ?'}",
          variables: [encodedIds, if (table != 'tasks') Variable(table)],
        )
        .get();
    final blocked = pending.map((r) => r.read<String>('entity_id')).toSet();
    final markers = await db
        .customSelect(
          'SELECT key FROM app_settings WHERE key IN (SELECT value FROM json_each(?))',
          variables: [
            Variable(jsonEncode(ids.map((id) => 'purged:$table:$id').toList())),
          ],
        )
        .get();
    final purged = markers.map((r) => r.read<String>('key')).toSet();
    final changed = <Map<String, dynamic>>[];
    var highest = 0;
    for (final raw in rows) {
      final id = raw['id'] as String;
      final counter = raw['logical_version'] as int;
      if (counter > highest) highest = counter;
      if (blocked.contains(id) || purged.contains('purged:$table:$id')) {
        continue;
      }
      final old = local[id];
      if (old != null &&
          domain.LogicalVersion(counter, raw['device_id'] as String).compareTo(
                domain.LogicalVersion(
                  old.read<int>('logical_version'),
                  old.read<String>('device_id'),
                ),
              ) <=
              0) {
        continue;
      }
      changed.add(raw);
    }
    final counter = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals('sync_lamport_counter'))).getSingleOrNull();
    if (highest > (int.tryParse(counter?.value ?? '') ?? 0)) {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: 'sync_lamport_counter',
              value: '$highest',
            ),
          );
    }
    scope.check();
    if (changed.isNotEmpty) {
      Map<String, dynamic> projectJson(Map<String, dynamic> raw) => {
        for (final e in normalizeProject(raw).entries)
          e.key.replaceAllMapped(
            RegExp('_([a-z])'),
            (m) => m[1]!.toUpperCase(),
          ): e.value,
      };
      await db.batch((batch) {
        if (table == 'tasks') {
          batch.insertAllOnConflictUpdate(
            db.tasks,
            changed.map(taskFromRemote),
          );
        } else if (table == 'projects') {
          batch.insertAllOnConflictUpdate(
            db.projects,
            changed.map((r) => Project.fromJson(projectJson(r))),
          );
        } else {
          batch.insertAllOnConflictUpdate(
            db.projectSections,
            changed.map((r) => ProjectSection.fromJson(projectJson(r))),
          );
        }
      });
    }
    scope.check();
    return changed.map((r) => r['id'] as String).toSet();
  });
}
