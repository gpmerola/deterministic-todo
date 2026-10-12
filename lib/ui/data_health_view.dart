part of '../main.dart';

class DataHealthView extends StatelessWidget {
  const DataHealthView({required this.repository, this.syncService, super.key});

  final TaskRepository repository;
  final SyncService? syncService;

  Future<({int tasks, int projects, int pending, String? backup, String? auto})>
  _snapshot() async {
    final tasks = await repository.db.select(repository.db.tasks).get();
    final projects = await repository.db.select(repository.db.projects).get();
    final pending = await repository.db
        .select(repository.db.outboxEntries)
        .get();
    final backup = await (repository.db.select(
      repository.db.appSettings,
    )..where((row) => row.key.equals('last_backup_at'))).getSingleOrNull();
    final auto =
        await (repository.db.select(repository.db.appSettings)
              ..where((row) => row.key.equals(AutoBackupService.lastAtKey)))
            .getSingleOrNull();
    return (
      auto: auto?.value,
      tasks: tasks.length,
      projects: projects.where((item) => !item.isArchived).length,
      pending: pending.length,
      backup: backup?.value,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _snapshot(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.requireData;
      return StreamBuilder<SyncSnapshot>(
        stream: syncService?.snapshots,
        initialData: syncService?.latest,
        builder: (context, syncSnapshot) {
          final sync = syncSnapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              _HealthRow(
                ok: sync?.phase != SyncPhase.error,
                icon: Icons.sync,
                title: 'Sincronizzazione',
                value: switch (sync?.phase) {
                  SyncPhase.current => 'Aggiornata',
                  SyncPhase.syncing => 'In corso',
                  SyncPhase.error => 'Da controllare',
                  SyncPhase.offline => 'Offline',
                  _ => 'Locale',
                },
              ),
              _HealthRow(
                ok: sync?.alignment?.aligned ?? true,
                icon: Icons.compare_arrows,
                title: 'Allineamento con il server',
                value: syncAlignmentLabel(sync?.alignment),
              ),
              if (sync?.alignment?.aligned == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton.icon(
                    onPressed: sync?.phase == SyncPhase.syncing
                        ? null
                        : syncService?.repairAlignment,
                    icon: const Icon(Icons.healing_outlined),
                    label: const Text('Riscarica tutto dal server'),
                  ),
                ),
              _HealthRow(
                ok: data.pending == 0,
                icon: Icons.outbox_outlined,
                title: 'Modifiche in attesa',
                value: '${data.pending}',
              ),
              if (sync?.retryAt != null)
                _HealthRow(
                  ok: false,
                  icon: Icons.schedule_outlined,
                  title: 'Nuovo tentativo',
                  value: DateFormat(
                    'HH:mm:ss',
                    'it',
                  ).format(sync!.retryAt!.toLocal()),
                ),
              if (sync?.lastFailure != null)
                _HealthRow(
                  ok:
                      sync?.lastRecovery != null &&
                      sync!.lastRecovery!.isAfter(sync.lastFailure!),
                  icon: Icons.troubleshoot_outlined,
                  title: 'Ultimo problema sync',
                  value: _syncIncidentLabel(sync!),
                ),
              if (sync?.lastSuccess != null)
                _HealthRow(
                  ok: true,
                  icon: Icons.cloud_done_outlined,
                  title: 'Ultimo sync riuscito',
                  value: DateFormat(
                    'd MMM, HH:mm:ss',
                    'it',
                  ).format(sync!.lastSuccess!.toLocal()),
                ),
              _HealthRow(
                ok: true,
                icon: Icons.storage_outlined,
                title: 'Dati locali',
                value: '${data.tasks} attività · ${data.projects} progetti',
              ),
              _HealthRow(
                ok: data.backup != null,
                icon: Icons.backup_outlined,
                title: 'Ultimo backup',
                value: data.backup == null
                    ? 'Non ancora esportato'
                    : DateFormat(
                        'd MMM, HH:mm',
                        'it',
                      ).format(DateTime.parse(data.backup!).toLocal()),
              ),
              if (isAndroidPlatform)
                _HealthRow(
                  ok: data.auto != null,
                  icon: Icons.enhanced_encryption_outlined,
                  title: 'Backup automatico cifrato',
                  value: data.auto == null
                      ? 'Non attivo: Dati e manutenzione → Backup automatici'
                      : DateFormat(
                          'd MMM, HH:mm',
                          'it',
                        ).format(DateTime.parse(data.auto!).toLocal()),
                ),
              FutureBuilder<PackageInfo>(
                future: appPackageInfo(),
                builder: (context, package) => _HealthRow(
                  ok: true,
                  icon: Icons.verified_outlined,
                  title: 'Versione',
                  value: package.hasData
                      ? '${package.requireData.version} '
                            '(${package.requireData.buildNumber})'
                      : 'Controllo…',
                ),
              ),
              if (sync?.phase == SyncPhase.error || data.pending > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.icon(
                    onPressed: syncService?.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Riprova sincronizzazione'),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

/// Bucket fingerprints count groups of tasks, not single tasks.
@visibleForTesting
String syncAlignmentLabel(SyncAlignment? alignment) {
  if (alignment == null) return 'Non ancora verificato';
  final time = DateFormat(
    'd MMM, HH:mm',
    'it',
  ).format(alignment.checkedAt.toLocal());
  final scope = alignment.contentChecked ? '' : ' · solo versioni';
  final repaired = alignment.repaired ? ' · dopo download completo' : '';
  if (alignment.aligned) return 'Allineato · $time$scope$repaired';
  final n = alignment.divergedBuckets;
  return '${n == 1 ? '1 gruppo diverso' : '$n gruppi diversi'} dal server'
      ' · $time$scope$repaired';
}

String _syncIncidentLabel(SyncSnapshot snapshot) {
  final timestamp = DateFormat(
    'd MMM, HH:mm:ss',
    'it',
  ).format(snapshot.lastFailure!.toLocal());
  final stage = switch (snapshot.lastFailureStage) {
    SyncStage.overview => 'controllo versioni',
    SyncStage.projects => 'progetti',
    SyncStage.taskUpload => 'invio attività',
    SyncStage.receipt => 'ricevuta outbox',
    SyncStage.taskPull => 'download attività',
    SyncStage.taskMerge => 'confronto locale',
    SyncStage.purgePull => 'registro eliminazioni',
    _ => 'avvio',
  };
  final recovered =
      snapshot.lastRecovery != null &&
      snapshot.lastRecovery!.isAfter(snapshot.lastFailure!);
  return '$timestamp · $stage · ${snapshot.lastError ?? 'errore'}'
      '${recovered ? ' · recuperato' : ''}';
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.ok,
    required this.icon,
    required this.title,
    required this.value,
  });

  final bool ok;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(value),
    trailing: Icon(
      ok ? Icons.check_circle : Icons.error_outline,
      color: ok ? Colors.green : Theme.of(context).colorScheme.error,
    ),
  );
}
