import 'package:drift/drift.dart';

import 'local/database.dart';

/// Counts only: diagnostic screens must not materialize user content.
Future<({int tasks, int projects, int pending})> diagnosticCounts(
  AppDatabase db,
) async {
  final row = await db.customSelect('''
    SELECT (SELECT COUNT(*) FROM tasks) AS tasks,
      (SELECT COUNT(*) FROM projects WHERE is_archived = 0) AS projects,
      (SELECT COUNT(*) FROM outbox_entries) AS pending
  ''').getSingle();
  return (
    tasks: row.read<int>('tasks'),
    projects: row.read<int>('projects'),
    pending: row.read<int>('pending'),
  );
}

/// One latest operation per entity, grouping task upsert/delete together.
/// Window functions preserve the previous created_at/rowid tie-break without
/// transferring payload JSON into the UI. Page size bounds result allocation.
Stream<List<QueryRow>> watchSyncIssues(
  AppDatabase db, {
  required int offset,
  int pageSize = 50,
}) => db
    .customSelect(
      '''
    WITH ranked AS (
      SELECT entity_id, last_error,
        CASE WHEN operation IN ('upsert', 'delete') THEN 'tasks' ELSE operation END AS kind,
        ROW_NUMBER() OVER (
          PARTITION BY CASE WHEN operation IN ('upsert', 'delete') THEN 'tasks' ELSE operation END, entity_id
          ORDER BY created_at DESC, rowid DESC) AS rank,
        MIN(created_at) OVER (
          PARTITION BY CASE WHEN operation IN ('upsert', 'delete') THEN 'tasks' ELSE operation END, entity_id) AS first_at,
        FIRST_VALUE(rowid) OVER (
          PARTITION BY CASE WHEN operation IN ('upsert', 'delete') THEN 'tasks' ELSE operation END, entity_id ORDER BY created_at, rowid) AS first_row
      FROM outbox_entries
    )
    SELECT r.entity_id, r.last_error, r.kind,
      COALESCE(t.title, p.name, s.name, 'Elemento da sincronizzare') AS entity_label
    FROM ranked r
    LEFT JOIN tasks t ON r.kind = 'tasks' AND t.id = r.entity_id
    LEFT JOIN projects p ON r.kind = 'projects' AND p.id = r.entity_id
    LEFT JOIN project_sections s ON r.kind = 'project_sections' AND s.id = r.entity_id
    WHERE r.rank = 1
    ORDER BY r.first_at, r.first_row, r.kind, r.entity_id
    LIMIT ? OFFSET ?
  ''',
      variables: [Variable.withInt(pageSize + 1), Variable.withInt(offset)],
      readsFrom: {db.outboxEntries, db.tasks, db.projects, db.projectSections},
    )
    .watch();
