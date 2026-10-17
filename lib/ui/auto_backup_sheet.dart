import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/auto_backup_service.dart';

/// Lists the encrypted automatic backups. Returns an [AutoBackupEntry] or
/// [AutoBackupSheet.fromFile]; the caller previews before any import.
/// Activation, "Crea ora" and showing the code are its only actions.
class AutoBackupSheet extends StatefulWidget {
  const AutoBackupSheet({required this.backups, super.key});
  final AutoBackupService backups;

  static const fromFile = 'file';

  @override
  State<AutoBackupSheet> createState() => _AutoBackupSheetState();
}

class _AutoBackupSheetState extends State<AutoBackupSheet> {
  late Future<AutoBackupStatus> state = widget.backups.status();
  bool busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operazione non riuscita'),
            showCloseIcon: true,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      state = widget.backups.status();
    });
  }

  Future<void> _activate() => _run(() async {
    final code = await widget.backups.activate();
    if (mounted) await showRecoveryCodeDialog(context, code, first: true);
  });

  String _date(DateTime? value) => value == null
      ? 'Mai'
      : DateFormat('d MMM y, HH:mm', 'it').format(value.toLocal());

  Future<void> _showCode() => _run(() async {
    final code = await widget.backups.recoveryCode();
    if (mounted) await showRecoveryCodeDialog(context, code, first: false);
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<AutoBackupStatus>(
      future: state,
      builder: (context, snapshot) {
        final configured = snapshot.data?.configured ?? false;
        final items = snapshot.data?.files ?? const <AutoBackupEntry>[];
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Backup automatici'),
              subtitle: Text(
                'Una copia cifrata a settimana in Documenti/Todo backup, '
                'solo se qualcosa è cambiato; restano le ultime '
                '${AutoBackupService.keep}. Su un altro telefono serve il '
                'codice di ripristino.',
              ),
            ),
            if (snapshot.hasError || snapshot.data?.unavailable == true)
              const ListTile(title: Text('Stato non disponibile'))
            else if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (!configured)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: busy ? null : _activate,
                  icon: const Icon(Icons.enhanced_encryption_outlined),
                  label: const Text('Attiva e mostra il codice'),
                ),
              )
            else ...[
              if (snapshot.data!.lastAttemptFailed)
                const ListTile(
                  title: Text('Ultimo backup non riuscito'),
                  subtitle: Text(
                    'La configurazione è attiva. Riprova con Crea ora.',
                  ),
                ),
              ListTile(
                title: const Text('Ultimo controllo dei contenuti'),
                subtitle: Text(_date(snapshot.data!.checkedAt)),
              ),
              ListTile(
                title: const Text('Ultima copia creata'),
                subtitle: Text(_date(snapshot.data!.createdAt)),
              ),
              if (!snapshot.data!.available && items.isNotEmpty)
                const ListTile(
                  title: Text('Ultima copia non disponibile'),
                  subtitle: Text(
                    'Restano copie precedenti. Usa Crea ora per ricrearla.',
                  ),
                ),
              if (items.isEmpty)
                const ListTile(title: Text('Nessun backup ancora')),
              for (final entry in items.reversed)
                ListTile(
                  leading: const Icon(Icons.lock_clock_outlined),
                  title: Text(
                    DateFormat(
                      'EEEE d MMMM y, HH:mm',
                      'it',
                    ).format(entry.savedAt.toLocal()),
                  ),
                  subtitle: Text(
                    '${(entry.size / 1024).ceil()} KB · tocca per '
                    'l’anteprima del ripristino',
                  ),
                  onTap: busy ? null : () => Navigator.pop(context, entry),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _run(() => widget.backups.backupNow()),
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Crea ora'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : _showCode,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Codice di ripristino'),
                  ),
                ],
              ),
            ],
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Ripristina da file .tdb'),
              enabled: !busy,
              onTap: () => Navigator.pop(context, AutoBackupSheet.fromFile),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showRecoveryCodeDialog(
  BuildContext context,
  String code, {
  required bool first,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    title: const Text('Codice di ripristino'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first
              ? 'Salvalo nel gestore password. Senza questo codice i backup '
                    'non si possono aprire su un altro telefono o dopo una '
                    'reinstallazione.'
              : 'Lo stesso codice vale per tutti i backup di questa '
                    'installazione.',
        ),
        const SizedBox(height: 12),
        SelectableText(
          code,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: code)),
        child: const Text('Copia'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(first ? 'Ho salvato il codice' : 'Chiudi'),
      ),
    ],
  ),
);
