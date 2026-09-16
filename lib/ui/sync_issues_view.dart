import 'package:drift/drift.dart' show QueryRow;

import 'package:flutter/material.dart';

import '../data/local/database.dart';
import '../data/sync/sync_service.dart';
import '../data/task_repository.dart';
import 'activity_history_view.dart';

class SyncIssuesView extends StatelessWidget {
  const SyncIssuesView({
    required this.repository,
    required this.service,
    super.key,
  });
  final TaskRepository repository;
  final SyncService service;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sincronizzazione')),
    body: StreamBuilder<List<QueryRow>>(
      stream: repository.db
          .customSelect(
            '''
        SELECT o.*, COALESCE(t.title, p.name, s.name, 'Elemento da sincronizzare') AS entity_label
        FROM outbox_entries o
        LEFT JOIN tasks t ON t.id = o.entity_id AND o.operation IN ('upsert', 'delete')
        LEFT JOIN projects p ON p.id = o.entity_id AND o.operation = 'projects'
        LEFT JOIN project_sections s ON s.id = o.entity_id AND o.operation = 'project_sections'
        ORDER BY o.created_at, o.rowid
        ''',
            readsFrom: {
              repository.db.outboxEntries,
              repository.db.tasks,
              repository.db.projects,
              repository.db.projectSections,
            },
          )
          .watch(),
      builder: (context, snapshot) {
        final groups = <String, (OutboxEntry, String)>{};
        for (final row in snapshot.data ?? <QueryRow>[]) {
          final e = repository.db.outboxEntries.map(row.data);
          groups['${e.operation == 'upsert' || e.operation == 'delete' ? 'tasks' : e.operation}:${e.entityId}'] =
              (e, row.read<String>('entity_label'));
        }
        return ListView(
          children: [
            const ListTile(
              title: Text('Le modifiche sono salvate su questo dispositivo.'),
              subtitle: Text(
                'Un elemento in conflitto non blocca gli altri. Apri lo storico per confrontare le versioni e scegliere.',
              ),
            ),
            for (final group in groups.values)
              Builder(
                builder: (context) {
                  final e = group.$1;
                  return ListTile(
                    leading: Icon(
                      e.lastError == null
                          ? Icons.cloud_upload_outlined
                          : Icons.sync_problem,
                    ),
                    title: Text(group.$2),
                    subtitle: Text(
                      e.lastError == 'intent_conflict'
                          ? 'Serve una scelta'
                          : e.lastError == 'purged_entity'
                          ? 'Eliminato definitivamente su un altro dispositivo'
                          : 'Da sincronizzare',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityHistoryView(
                          repository: repository,
                          entityId: e.entityId,
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (groups.isEmpty)
              const ListTile(title: Text('Nessuna modifica in attesa')),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => service.sync(),
                child: const Text('Controlla sincronizzazione'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
