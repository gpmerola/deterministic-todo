part of '../../main.dart';

/// Once-a-day housekeeping started by the shell: archive old completions
/// and the performance diagnostics reminder.
extension _ShellMaintenance on _TaskShellState {
  Future<void> _runDailyMaintenance() async {
    final today = CivilDate.fromDateTime(DateTime.now()).toString();
    final setting = await (widget.repository.db.select(
      widget.repository.db.appSettings,
    )..where((row) => row.key.equals('maintenance_date'))).getSingleOrNull();
    if (setting?.value == today) return;
    await widget.repository.archiveCompletedOlderThan(
      DateTime.now().subtract(const Duration(days: 365)),
    );
    await _savePreference('maintenance_date', today);
  }

  Future<void> _showDailyPerformanceReminder() async {
    if (!DiagnosticLogService.instance.isInitialized) return;
    final today = CivilDate.fromDateTime(DateTime.now()).toString();
    final setting =
        await (widget.repository.db.select(widget.repository.db.appSettings)
              ..where((row) => row.key.equals('performance_reminder_date')))
            .getSingleOrNull();
    if (setting?.value == today || !mounted) return;
    await widget.repository.db
        .into(widget.repository.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'performance_reminder_date',
            value: today,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        persist: false,
        showCloseIcon: true,
        content: const Text('Diagnostica prestazioni disponibile'),
        action: SnackBarAction(
          label: 'Apri',
          onPressed: _showPerformanceDialog,
        ),
      ),
    );
  }

  Future<void> _showPerformanceDialog() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Controllare le prestazioni?'),
      content: const Text(
        'Se hai usato abbastanza l’app, puoi esportare i log e inviarli a '
        'Codex con questo prompt:\n\n“Analizza questi log prestazionali, '
        'individua colli di bottiglia di RAM, CPU, storage, frame e sync e '
        'implementa le ottimizzazioni sicure.”',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Non oggi'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(
                text:
                    'Analizza questi log prestazionali, individua colli di '
                    'bottiglia di RAM, CPU, storage, frame e sync e '
                    'implementa le ottimizzazioni sicure.',
              ),
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Copia prompt'),
        ),
        FilledButton(
          onPressed: () async {
            final data = await DiagnosticLogService.instance.exportData();
            if (data != null) {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile.fromData(
                      data.bytes,
                      name: data.name,
                      mimeType: 'application/x-ndjson',
                    ),
                  ],
                  fileNameOverrides: [data.name],
                  title: 'Diagnostica Deterministic Todo',
                ),
              );
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Esporta log'),
        ),
      ],
    ),
  );
}
