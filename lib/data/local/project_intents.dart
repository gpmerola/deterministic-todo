part of 'database.dart';

/// Capture all canonical project writers, including imports, atomically.
Future<void> _installProjectIntents(
  AppDatabase db, {
  bool migrate = false,
}) async {
  for (final table in <TableInfo<Table, DataClass>>[
    db.projects,
    db.projectSections,
  ]) {
    final name = table.actualTableName;
    String snapshot(String alias) =>
        'json_object(${table.$columns.map((c) => "'${c.$name}', $alias.\"${c.$name}\"").join(', ')})';
    final after = snapshot('NEW');
    final before = snapshot('OLD');
    for (final operation in ['INSERT', 'UPDATE']) {
      final changes = operation == 'INSERT'
          ? "json('{}')"
          : '''(
        SELECT json_group_object(n.key, n.value) FROM json_each($after) n
        JOIN json_each($before) o ON n.key = o.key
        WHERE n.value IS NOT o.value AND n.key NOT IN ('id', 'user_id', 'device_id', 'logical_version')
      )''';
      await db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${name}_intent_${operation.toLowerCase()}
        AFTER $operation ON "$name"
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '_revision_source'), '') NOT LIKE 'sync_%'
        ${operation == 'UPDATE' ? "AND $changes != '{}'" : ''}
        BEGIN
          INSERT INTO outbox_entries(operation_id, entity_id, operation, payload, created_at)
          VALUES(lower(hex(randomblob(16))), NEW.id, '$name',
            json_object('schema', 3, 'table', '$name', 'kind', CASE WHEN (SELECT value FROM app_settings WHERE key = '_revision_source') = 'backup_import'
                THEN 'replace' ELSE '${operation == 'INSERT' ? 'create' : 'patch'}' END,
              'snapshot', json($after), 'changes', json($changes)),
            CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER));
        END
      ''');
    }
    if (migrate) {
      final prefix = name == 'projects' ? 'sync_project:' : 'sync_section:';
      final rows = await db.customSelect('SELECT * FROM "$name"').get();
      for (final row in rows) {
        final data = row.data;
        final id = data['id'] as String;
        final synced = await (db.select(
          db.appSettings,
        )..where((r) => r.key.equals('$prefix$id'))).getSingleOrNull();
        if (synced?.value ==
            '${data['logical_version']}:${data['device_id']}') {
          continue;
        }
        await db
            .into(db.outboxEntries)
            .insert(
              OutboxEntriesCompanion.insert(
                operationId: const Uuid().v5(
                  '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
                  'migration8:$name:$id',
                ),
                entityId: id,
                operation: name,
                payload: jsonEncode({
                  'schema': 3,
                  'table': name,
                  'kind': 'legacy',
                  'snapshot': data,
                }),
                createdAt: DateTime.now().toUtc().microsecondsSinceEpoch,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }
}
