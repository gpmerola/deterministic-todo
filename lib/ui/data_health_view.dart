part of '../main.dart';

class DataHealthView extends StatelessWidget {
  const DataHealthView({required this.repository, this.syncService, super.key});

  final TaskRepository repository;
  final SyncService? syncService;

  Future<({int tasks, int projects, int pending, String? backup})>
  _snapshot() async {
    final tasks = await repository.db.select(repository.db.tasks).get();
    final projects = await repository.db.select(repository.db.projects).get();
    final pending = await repository.db
        .select(repository.db.outboxEntries)
        .get();
    final backup = await (repository.db.select(
      repository.db.appSettings,
    )..where((row) => row.key.equals('last_backup_at'))).getSingleOrNull();
    return (
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
                ok: data.pending == 0,
                icon: Icons.outbox_outlined,
                title: 'Modifiche in attesa',
                value: '${data.pending}',
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
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
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
