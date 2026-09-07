part of 'database.dart';

/// SQLite triggers cover local edits, imports, deletes and remote writes alike.
/// This archive is private application data, never part of diagnostic log export.
Future<void> _installRevisionTriggers(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS revisions_entity_idx ON '
    'activity_revisions(entity_type, entity_id, sequence DESC)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS revisions_time_idx ON '
    'activity_revisions(recorded_at)',
  );
  for (final table in <TableInfo<Table, DataClass>>[
    db.tasks,
    db.projects,
    db.projectSections,
  ]) {
    final name = table.actualTableName;
    String snapshot(String alias) =>
        'json_object(${table.$columns.map((column) => "'${column.$name}', $alias.\"${column.$name}\"").join(', ')})';
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final before = operation == 'INSERT' ? 'NULL' : snapshot('OLD');
      final after = operation == 'DELETE' ? 'NULL' : snapshot('NEW');
      final alias = operation == 'DELETE' ? 'OLD' : 'NEW';
      final condition = operation == 'UPDATE' ? 'WHEN $before != $after' : '';
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${name}_history_${operation.toLowerCase()}
        AFTER $operation ON "$name" $condition
        BEGIN
          INSERT INTO activity_revisions
            (entity_type, entity_id, operation, source, recorded_at, before_json, after_json)
          VALUES ('$name', $alias.id, '${operation.toLowerCase()}',
            COALESCE((SELECT value FROM app_settings WHERE key = '_revision_source'), 'local_write'),
            CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER),
            $before, $after);
        END
      ''');
    }
  }
}

extension RevisionAccess on AppDatabase {
  Future<T> withRevisionSource<T>(String source, Future<T> Function() body) =>
      transaction(() async {
        final prior =
            await (select(appSettings)
                  ..where((row) => row.key.equals('_revision_source')))
                .getSingleOrNull();
        await into(appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: '_revision_source', value: source),
        );
        try {
          return await body();
        } finally {
          if (prior == null) {
            await (delete(
              appSettings,
            )..where((row) => row.key.equals('_revision_source'))).go();
          } else {
            await into(appSettings).insertOnConflictUpdate(prior);
          }
        }
      });

  Future<void> recordSyncRevision({
    required String entityId,
    required String source,
    required Map<String, dynamic>? before,
    required Map<String, dynamic>? after,
    required List<String> operationIds,
  }) async {
    final eventKey = jsonEncode([
      source,
      entityId,
      operationIds,
      before?['logical_version'],
      before?['device_id'],
      after?['logical_version'],
      after?['device_id'],
    ]);
    await into(activityRevisions).insert(
      ActivityRevisionsCompanion.insert(
        entityType: 'tasks',
        entityId: entityId,
        operation: 'sync',
        source: source,
        recordedAt: DateTime.now().toUtc().microsecondsSinceEpoch,
        beforeJson: Value(before == null ? null : jsonEncode(before)),
        afterJson: Value(after == null ? null : jsonEncode(after)),
        operationIds: Value(jsonEncode(operationIds)),
        eventKey: Value(eventKey),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
