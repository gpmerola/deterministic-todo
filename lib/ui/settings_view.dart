part of '../main.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.repository,
    required this.checkForUpdates,
    required this.showCompleted,
    this.syncClient,
    this.syncService,
    super.key,
  });

  final TaskRepository repository;
  final Future<void> Function() checkForUpdates;
  final VoidCallback showCompleted;
  final SupabaseClient? syncClient;
  final SyncService? syncService;

  Future<void> _export(BuildContext context, bool json) async {
    final service = ExportService(repository.db);
    final content = json
        ? await service.exportJson()
        : await service.exportCsv();
    final name = 'attivita.${json ? 'json' : 'csv'}';
    if (context.mounted) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(content)),
              name: name,
              mimeType: json ? 'application/json' : 'text/csv',
            ),
          ],
          fileNameOverrides: [name],
          title: 'Esporta attività',
        ),
      );
      await repository.db
          .into(repository.db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: 'last_backup_at',
              value: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    }
  }

  Future<void> _import(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || !context.mounted) return;
    final bytes = picked.files.single.bytes;
    final source = await readPickedText(bytes, picked.files.single.path);
    final service = ExportService(repository.db);
    final preview = await service.preview(source);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anteprima importazione'),
        content: Text(
          'Da aggiungere: ${preview.added}\nDa aggiornare: ${preview.updated}\nInvariate: ${preview.unchanged}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.importValidated(source);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Importazione completata'),
            showCloseIcon: true,
          ),
        );
      }
    }
  }

  Future<void> _importTodoist(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || !context.mounted) return;
      final bytes = picked.files.single.bytes;
      final source = await readPickedText(bytes, picked.files.single.path);
      const service = TodoistImportService();
      // JSON e normalizzazione possono essere costosi su export grandi. Su
      // Android compute usa un isolate; sul Web mantiene la stessa API.
      final plan = await compute(parseTodoistImportPlan, source);
      final preview = plan.preview;
      if (!context.mounted) return;
      final priorities = List.generate(
        4,
        (index) => 'P${4 - index}: ${preview.priorityCounts[index + 1] ?? 0}',
      ).join(' · ');
      final unsupported = preview.unsupportedRecurrences;
      final mode = await showDialog<TodoistImportMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Anteprima Todoist'),
          content: SingleChildScrollView(
            child: Text(
              '${preview.projects} progetti\n'
              '${preview.sections} sezioni\n'
              '${preview.activeTasks} attività attive '
              '(${preview.scheduledTasks} pianificate, '
              '${preview.recurringTasks} ricorrenti)\n'
              '$priorities'
              '${unsupported.isEmpty ? '' : '\n\nDa verificare: '
                        '${unsupported.join(', ')}'}\n\n'
              'Le attività completate non saranno importate. '
              '“Aggiorna” aggiunge e aggiorna senza duplicati e conserva le '
              'attività completate nell’app. “Sostituisci” ricostruisce da '
              'zero solo i dati Todoist; le attività create nell’app non '
              'vengono toccate.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: unsupported.isEmpty
                  ? () async {
                      final replace = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Sostituire i dati Todoist?'),
                          content: const Text(
                            'Le vecchie attività, sezioni e progetti importati '
                            'da Todoist che non compaiono nel nuovo JSON '
                            'saranno rimossi. Quelli presenti saranno '
                            'ripristinati dal file. I dati creati direttamente '
                            'nell’app resteranno invariati.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('No, annulla'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sostituisci da zero'),
                            ),
                          ],
                        ),
                      );
                      if (replace == true && context.mounted) {
                        Navigator.pop(context, TodoistImportMode.replace);
                      }
                    }
                  : null,
              child: const Text('Sostituisci'),
            ),
            FilledButton(
              onPressed: unsupported.isEmpty
                  ? () => Navigator.pop(context, TodoistImportMode.incremental)
                  : null,
              child: const Text('Aggiorna'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      if (syncClient?.auth.currentUser != null) {
        await syncClient!.from('projects').select('id').limit(1);
        await syncClient!.from('project_sections').select('id').limit(1);
      }
      final result = await service.importPlan(
        plan: plan,
        db: repository.db,
        deviceId: repository.deviceId,
        mode: mode,
      );
      await DiagnosticLogService.instance.event(
        'todoist_import_completed',
        fields: {
          'tasks': result.addedTasks,
          'projects': result.addedProjects,
          'sections': result.addedSections,
          'updated': result.updatedTasks,
          'removed': result.removedTasks,
        },
      );
      await syncService?.sync();
      if (context.mounted) {
        await repository.db
            .into(repository.db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'last_todoist_import_at',
                value: DateTime.now().toUtc().toIso8601String(),
              ),
            );
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Import Todoist completato'),
            content: Text(
              '${preview.activeTasks} attività attive lette\n'
              '${result.addedTasks} aggiunte · ${result.updatedTasks} aggiornate\n'
              '${result.removedTasks} rimosse perché assenti dal nuovo JSON\n'
              '${preview.projects} progetti · ${preview.sections} sezioni\n'
              '${preview.recurringTasks} ricorrenti · '
              '${preview.scheduledTasks} pianificate\n\n'
              'Elementi non importati: attività completate, commenti, '
              'allegati, filtri e promemoria Todoist.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Chiudi'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _export(context, true);
                },
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Backup ora'),
              ),
            ],
          ),
        );
      }
    } on FormatException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message), showCloseIcon: true),
      );
    } on PostgrestException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Prima esegui in Supabase la migrazione '
            '202608040002_todoist_import.sql. Nessun dato è stato importato.',
          ),
          showCloseIcon: true,
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Import Todoist non riuscito: nessun dato modificato.'),
          showCloseIcon: true,
        ),
      );
    }
  }

  Future<void> _exportDiagnostics(BuildContext context) async {
    final data = await DiagnosticLogService.instance.exportData();
    if (data == null || !context.mounted) return;
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

  Future<void> _resetLocalData(BuildContext context) async {
    if (syncClient?.auth.currentUser != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sincronizzazione ancora collegata'),
          content: const Text(
            'Prima scollega questo dispositivo. Altrimenti i dati verrebbero '
            'scaricati di nuovo da Supabase subito dopo la cancellazione.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancellare tutti i dati locali?'),
        content: const Text(
          'Attività, progetti, sezioni e preferenze saranno cancellati in '
          'un’unica operazione. Questa azione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancella tutto'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.resetAllLocalData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dati locali cancellati'),
          showCloseIcon: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
    children: [
      SyncAccountCard(client: syncClient, syncService: syncService),
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) => ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(
            isPlayDistribution
                ? 'Aggiorna da Google Play'
                : 'Controlla aggiornamenti',
          ),
          subtitle: Text(
            snapshot.hasData
                ? 'Versione ${snapshot.requireData.version} '
                      '(${snapshot.requireData.buildNumber})'
                : isPlayDistribution
                ? 'Apri la scheda Google Play'
                : 'Verifica la release pubblica più recente',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: checkForUpdates,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.health_and_safety_outlined),
        title: const Text('Salute dati'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: DataHealthView(
              repository: repository,
              syncService: syncService,
            ),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: const Text('Attività completate'),
        trailing: const Icon(Icons.chevron_right),
        onTap: showCompleted,
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline),
        title: const Text('Cestino'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          sheetAnimationStyle: const AnimationStyle(
            duration: Duration.zero,
            reverseDuration: Duration.zero,
          ),
          builder: (_) =>
              TrashView(repository: repository, syncService: syncService),
        ),
      ),
      ExpansionTile(
        leading: const Icon(Icons.storage_outlined),
        title: const Text('Dati e manutenzione'),
        children: [
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Esporta backup'),
            onTap: () => _export(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Esporta CSV'),
            onTap: () => _export(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Importa backup'),
            onTap: () => _import(context),
          ),
          ListTile(
            leading: const Icon(Icons.task_alt_outlined),
            title: const Text('Importa da Todoist'),
            onTap: () => _importTodoist(context),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Esporta diagnostica'),
            onTap: () => _exportDiagnostics(context),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Cancella tutti i dati locali'),
            onTap: () => _resetLocalData(context),
          ),
        ],
      ),
    ],
  );
}
