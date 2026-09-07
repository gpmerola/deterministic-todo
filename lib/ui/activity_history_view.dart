import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show OrderingMode, OrderingTerm, ComparableExpr;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local/database.dart';
import '../data/sync/task_sync_writer.dart';
import '../data/task_repository.dart';

class ActivityHistoryView extends StatefulWidget {
  const ActivityHistoryView({
    required this.repository,
    this.entityId,
    super.key,
  });
  final TaskRepository repository;
  final String? entityId;
  @override
  State<ActivityHistoryView> createState() => _ActivityHistoryViewState();
}

class _ActivityHistoryViewState extends State<ActivityHistoryView> {
  final rows = <ActivityRevision>[];
  bool loading = false;
  bool more = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      failed = false;
      if (refresh) rows.clear();
    });
    try {
      final db = widget.repository.db;
      final query = db.select(db.activityRevisions)
        ..orderBy([
          (r) => OrderingTerm(expression: r.sequence, mode: OrderingMode.desc),
        ])
        ..limit(50);
      if (widget.entityId != null) {
        query.where((r) => r.entityId.equals(widget.entityId!));
      }
      if (rows.isNotEmpty) {
        query.where((r) => r.sequence.isSmallerThanValue(rows.last.sequence));
      }
      final next = await query.get();
      if (!mounted) return;
      setState(() {
        rows.addAll(next);
        more = next.length == 50;
      });
    } on Object {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _export() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esporta storico'),
        content: const Text(
          'Il file include titoli, note e valori precedenti. Condividilo soltanto con chi può leggere questi dati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esporta'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final db = widget.repository.db;
      final query = db.select(db.activityRevisions)
        ..orderBy([(r) => OrderingTerm(expression: r.sequence)]);
      if (widget.entityId != null) {
        query.where((r) => r.entityId.equals(widget.entityId!));
      }
      final all = await query.get();
      final content = jsonEncode({
        'schema': 1,
        'scope': 'local_device',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'revisions': all.map((r) => r.toJson()).toList(),
      });
      await SharePlus.instance.share(
        ShareParams(
          title: 'Storico attività',
          fileNameOverrides: ['storico-attivita.json'],
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(content)),
              name: 'storico-attivita.json',
              mimeType: 'application/json',
            ),
          ],
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esportazione non riuscita. Lo storico è conservato.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _details(ActivityRevision row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _RevisionDetail(repository: widget.repository, revision: row),
      ),
    );
    if (mounted) await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Storico attività'),
      actions: [
        IconButton(
          onPressed: () => _load(refresh: true),
          tooltip: 'Aggiorna',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _export,
          tooltip: 'Esporta storico',
          icon: const Icon(Icons.ios_share),
        ),
      ],
    ),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Ultimi 90 giorni su questo dispositivo, a partire da questo aggiornamento. '
            'Le versioni restano locali; i log diagnostici non includono questi contenuti.',
          ),
        ),
        for (final row in rows)
          ListTile(
            leading: Icon(
              row.source == 'sync_conflict'
                  ? Icons.warning_amber
                  : Icons.history,
            ),
            title: Text(
              _title(row),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${_time(row.recordedAt)} · ${_source(row.source)}'),
            onTap: () => _details(row),
          ),
        if (rows.isEmpty && !loading && !failed)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nessuna modifica registrata.'),
          ),
        if (failed)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Lettura non riuscita. Riprova.'),
          ),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (more || failed)
          TextButton(onPressed: _load, child: const Text('Carica altre')),
      ],
    ),
  );
}

Map<String, dynamic> _snapshot(String? json) =>
    json == null ? {} : jsonDecode(json) as Map<String, dynamic>;
String _title(ActivityRevision row) {
  final snapshot = _snapshot(row.afterJson ?? row.beforeJson);
  return (snapshot['title'] ?? snapshot['name'] ?? 'Attività') as String;
}

String _time(int micros) => DateFormat(
  'dd/MM/yyyy HH:mm:ss',
).format(DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toLocal());
String _source(String value) => switch (value) {
  'user_import' => 'Importazione richiesta',
  'sync_pull' => 'Ricevuta dal server',
  'sync_attempt' => 'Tentativo di invio',
  'sync_accepted' => 'Invio confermato',
  'sync_confirmed' => 'Versione già presente',
  'sync_conflict' => 'Conflitto da risolvere',
  'user_restore' => 'Ripristino richiesto',
  _ => 'Modifica locale',
};

class _RevisionDetail extends StatelessWidget {
  const _RevisionDetail({required this.repository, required this.revision});
  final TaskRepository repository;
  final ActivityRevision revision;

  Future<void> _restore(
    BuildContext context,
    Map<String, dynamic> snapshot,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usa questa versione?'),
        content: const Text(
          'I valori selezionati diventeranno una nuova modifica da sincronizzare. La versione attuale resterà nello storico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usa questa versione'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.restoreRevision(taskFromRemote(snapshot));
      if (context.mounted) Navigator.pop(context);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ripristino non riuscito. Nessuna versione è stata eliminata.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final before = _snapshot(revision.beforeJson);
    final after = _snapshot(revision.afterJson);
    final keys = {
      ...before.keys,
      ...after.keys,
    }.where((key) => before[key] != after[key]).toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio modifica')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_title(revision), style: Theme.of(context).textTheme.titleLarge),
          Text('${_time(revision.recordedAt)} · ${_source(revision.source)}'),
          SelectableText(
            'ID: ${revision.entityId}\nOperazioni: ${revision.operationIds}',
          ),
          const SizedBox(height: 16),
          if (keys.isEmpty)
            const Text('Contenuti invariati; conferma della sincronizzazione.'),
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fieldLabels[key] ?? key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SelectableText(
                    'Prima: ${before[key] ?? "—"}\nDopo: ${after[key] ?? "—"}',
                  ),
                ],
              ),
            ),
          if (revision.entityType == 'tasks') ...[
            if (before.isNotEmpty)
              OutlinedButton(
                onPressed: () => _restore(context, before),
                child: const Text('Usa la versione precedente'),
              ),
            if (after.isNotEmpty)
              OutlinedButton(
                onPressed: () => _restore(context, after),
                child: const Text('Usa la versione successiva'),
              ),
          ],
        ],
      ),
    );
  }
}

const _fieldLabels = {
  'title': 'Titolo',
  'notes': 'Note',
  'status': 'Stato',
  'show_date': 'Data',
  'project_id': 'Progetto',
  'section_id': 'Sezione',
  'position': 'Ordine',
  'priority': 'Priorità',
  'logical_version': 'Versione',
  'device_id': 'Dispositivo autore',
  'updated_at': 'Istante della modifica (UTC, µs)',
  'completed_at': 'Completamento (UTC, µs)',
  'deleted_at': 'Eliminazione (UTC, µs)',
  'recurrence': 'Ricorrenza',
  'name': 'Nome',
};
