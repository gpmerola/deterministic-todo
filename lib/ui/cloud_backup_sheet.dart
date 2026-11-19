import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/cloud_backup_service.dart';

/// Copies of the Todo backup in the user's Supabase account. Returns the
/// [CloudBackupEntry] to restore; the caller previews it and asks for
/// confirmation before any import. "Crea ora" is its only other action.
class CloudBackupSheet extends StatefulWidget {
  const CloudBackupSheet({
    required this.backups,
    required this.deviceId,
    super.key,
  });
  final CloudBackupService backups;
  final String deviceId;

  @override
  State<CloudBackupSheet> createState() => _CloudBackupSheetState();
}

class _CloudBackupSheetState extends State<CloudBackupSheet> {
  late Future<CloudBackupStatus> state = widget.backups.status();
  bool busy = false;

  Future<void> _backupNow() async {
    setState(() => busy = true);
    String message;
    try {
      message = await widget.backups.backupNow()
          ? 'Copia salvata nel cloud'
          : 'Nessuna modifica dall’ultima copia nel cloud';
    } on Object {
      message = 'Copia nel cloud non riuscita';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
    setState(() {
      busy = false;
      state = widget.backups.status();
    });
  }

  String _date(DateTime? value) => value == null
      ? 'Mai'
      : DateFormat('d MMM y, HH:mm', 'it').format(value.toLocal());

  String _origin(CloudBackupEntry entry) => entry.deviceId == widget.deviceId
      ? 'questo dispositivo'
      : 'altro dispositivo';

  String _size(CloudBackupEntry entry) =>
      '${(entry.sizeBytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<CloudBackupStatus>(
      future: state,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final entries = status?.entries;
        final latest = status?.latest;
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Backup nel cloud'),
              subtitle: Text(
                'Una copia al giorno nel tuo account Supabase, solo se '
                'qualcosa è cambiato; restano le ultime '
                '${CloudBackupService.keep}. È protetta come le attività '
                'sincronizzate e si ripristina da qualsiasi telefono '
                'collegato allo stesso account.',
              ),
            ),
            if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (status!.lastAttemptFailed)
                const ListTile(
                  key: ValueKey('cloud-backup-failed'),
                  title: Text('Ultima copia nel cloud non riuscita'),
                  subtitle: Text('Riprova con Crea ora.'),
                ),
              if (entries == null)
                const ListTile(
                  key: ValueKey('cloud-backup-unavailable'),
                  title: Text('Copie nel cloud non raggiungibili'),
                  subtitle: Text(
                    'Controlla la connessione. Le attività non cambiano.',
                  ),
                )
              else ...[
                ListTile(
                  key: const ValueKey('cloud-backup-latest'),
                  title: const Text('Ultima copia nel cloud'),
                  subtitle: Text(
                    latest == null
                        ? 'Nessuna copia ancora'
                        : '${_date(latest.savedAt)} · ${_size(latest)} · '
                              'da ${_origin(latest)}',
                  ),
                ),
                if (latest != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('cloud-backup-restore-latest'),
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(context, latest),
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Ripristina l’ultima copia'),
                    ),
                  ),
                for (final entry in entries.skip(1))
                  ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: Text(
                      DateFormat(
                        'EEEE d MMMM y, HH:mm',
                        'it',
                      ).format(entry.savedAt.toLocal()),
                    ),
                    subtitle: Text(
                      '${_size(entry)} · da ${_origin(entry)} · tocca per '
                      'l’anteprima del ripristino',
                    ),
                    onTap: busy ? null : () => Navigator.pop(context, entry),
                  ),
              ],
              ListTile(
                title: const Text('Ultimo controllo da questo dispositivo'),
                subtitle: Text(_date(status.checkedAt)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('cloud-backup-now'),
                    onPressed: busy ? null : _backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Crea ora'),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
