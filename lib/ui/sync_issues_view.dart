import 'package:drift/drift.dart' show QueryRow;

import 'package:flutter/material.dart';

import '../data/diagnostic_queries.dart';
import '../data/sync/sync_service.dart';
import '../data/task_repository.dart';
import 'activity_history_view.dart';

class SyncIssuesView extends StatefulWidget {
  const SyncIssuesView({
    required this.repository,
    required this.service,
    super.key,
  });
  final TaskRepository repository;
  final SyncService service;

  @override
  State<SyncIssuesView> createState() => _SyncIssuesViewState();
}

class _SyncIssuesViewState extends State<SyncIssuesView> {
  static const pageSize = 50;
  int offset = 0;
  late Stream<List<QueryRow>> rows = _watch();
  Stream<List<QueryRow>> _watch() =>
      watchSyncIssues(widget.repository.db, offset: offset, pageSize: pageSize);
  void _page(int value) => setState(() {
    offset = value;
    rows = _watch();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sincronizzazione')),
    body: StreamBuilder<List<QueryRow>>(
      key: ValueKey(offset),
      stream: rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => _page(offset),
              child: const Text('Elenco non disponibile · Riprova'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.requireData;
        final groups = result.take(pageSize);
        return ListView(
          children: [
            const ListTile(
              title: Text('Le modifiche sono salvate su questo dispositivo.'),
              subtitle: Text(
                'Un elemento in conflitto non blocca gli altri. Apri lo storico per confrontare le versioni e scegliere.',
              ),
            ),
            for (final row in groups)
              Builder(
                builder: (context) {
                  final error = row.readNullable<String>('last_error');
                  return ListTile(
                    leading: Icon(
                      error == null
                          ? Icons.cloud_upload_outlined
                          : Icons.sync_problem,
                    ),
                    title: Text(row.read<String>('entity_label')),
                    subtitle: Text(
                      error == 'intent_conflict'
                          ? 'Serve una scelta'
                          : error == 'purged_entity'
                          ? 'Eliminato definitivamente su un altro dispositivo'
                          : error == 'server_rejected'
                          ? 'Rifiutato dal server: verrà ritentato senza bloccare gli altri'
                          : 'Da sincronizzare',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityHistoryView(
                          repository: widget.repository,
                          entityId: row.read<String>('entity_id'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (groups.isEmpty)
              ListTile(
                title: Text(
                  offset == 0
                      ? 'Nessuna modifica in attesa'
                      : 'Nessun altro elemento',
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: offset == 0
                      ? null
                      : () => _page(offset - pageSize),
                  child: const Text('Precedenti'),
                ),
                Text('Pagina ${offset ~/ pageSize + 1}'),
                TextButton(
                  onPressed: result.length > pageSize
                      ? () => _page(offset + pageSize)
                      : null,
                  child: const Text('Successivi'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => widget.service.sync(),
                child: const Text('Controlla sincronizzazione'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
