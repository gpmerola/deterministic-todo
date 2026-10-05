import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/agenda_backup.dart';

/// Status of the Supabase backup of Todo's own Agenda data, with "Salva
/// ora", "Ripristina" and, when the account holds a backup this phone has
/// not restored, "Usa questo telefono". True when the Agenda must reload.
Future<bool> showAgendaBackupSheet(
  BuildContext context,
  AgendaBackup backup,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AgendaBackupSheet(backup: backup),
    ) ??
    false;

class _AgendaBackupSheet extends StatefulWidget {
  const _AgendaBackupSheet({required this.backup});

  final AgendaBackup backup;

  @override
  State<_AgendaBackupSheet> createState() => _AgendaBackupSheetState();
}

class _AgendaBackupSheetState extends State<_AgendaBackupSheet> {
  RemoteAgendaBackup? remote;
  bool loading = true;
  bool working = false;
  String? message;

  /// The Agenda reloads after a restore.
  bool restored = false;

  bool get pending => AgendaBackup.pending.value != null;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final value = await widget.backup.remote();
      if (mounted) setState(() => remote = value);
    } catch (_) {
      if (mounted) setState(() => message = 'Backup non raggiungibile ora.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      working = true;
      message = null;
    });
    try {
      final text = await action();
      if (!mounted) return;
      setState(() => message = text);
      await _read();
    } catch (_) {
      if (mounted) setState(() => message = 'Operazione non riuscita.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  String _status(AgendaBackupStatus status) => switch (status) {
    AgendaBackupStatus.saved => 'Backup aggiornato.',
    AgendaBackupStatus.unchanged => 'Il backup era già aggiornato.',
    AgendaBackupStatus.conflict =>
      'Sull\'account c\'è un backup non ancora ripristinato qui.',
    AgendaBackupStatus.skipped => 'Serve l\'accesso alla sincronizzazione.',
    AgendaBackupStatus.failed => 'Backup non riuscito: riprova più tardi.',
  };

  Future<void> _restore(RemoteAgendaBackup value) => _run(() async {
    final added = await widget.backup.restore(value);
    restored = true;
    return added == 1
        ? 'Ripristinato: 1 evento aggiunto a Todo.'
        : 'Ripristinato: $added eventi aggiunti a Todo.';
  });

  Future<void> _replace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usare questo telefono?'),
        content: const Text(
          'Il backup sull\'account sarà sostituito da quello di questo '
          'telefono. Gli eventi Todo e le scelte che contiene e che qui '
          'mancano andranno persi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const ValueKey('agenda-backup-replace-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sostituisci'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async => _status(await widget.backup.save(force: true)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = remote;
    final when = DateFormat('EEE d MMM yyyy, HH:mm', 'it');
    return PopScope(
      canPop: !working,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Backup dell\'Agenda', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Sul tuo account Supabase: gli eventi di «Todo (solo '
                'telefono)», note comprese, gli eventi nascosti e le scelte '
                'dell\'Agenda. Gli altri calendari sono già nei loro account.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (loading)
                const LinearProgressIndicator()
              else if (value == null)
                const Text('Nessun backup ancora.')
              else
                Text(
                  key: const ValueKey('agenda-backup-status'),
                  'Ultimo backup: ${when.format(value.savedAt)}\n'
                  '${value.eventCount} eventi Todo · '
                  '${value.hiddenCount} nascosti',
                ),
              if (pending && value != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Questo backup non viene da questo telefono: finché non '
                  'scegli, non viene sovrascritto.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(message!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (value != null)
                    FilledButton.icon(
                      key: const ValueKey('agenda-backup-restore'),
                      onPressed: working ? null : () => _restore(value),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Ripristina'),
                    ),
                  if (pending)
                    OutlinedButton(
                      key: const ValueKey('agenda-backup-replace'),
                      onPressed: working ? null : _replace,
                      child: const Text('Usa questo telefono'),
                    )
                  else
                    OutlinedButton.icon(
                      key: const ValueKey('agenda-backup-save'),
                      onPressed: working
                          ? null
                          : () => _run(
                              () async => _status(await widget.backup.save()),
                            ),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Salva ora'),
                    ),
                  TextButton(
                    onPressed: working
                        ? null
                        : () => Navigator.pop(context, restored),
                    child: const Text('Chiudi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
