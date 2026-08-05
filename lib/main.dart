import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'data/local/database.dart';
import 'data/sync/secure_supabase_storage.dart';
import 'data/sync/sync_service.dart';
import 'data/task_repository.dart';
import 'domain/link_syntax.dart';
import 'domain/quick_add_metadata.dart';
import 'domain/quick_add_parser.dart';
import 'domain/task.dart';
import 'services/calendar_service.dart';
import 'services/diagnostic_log_service.dart';
import 'services/export_service.dart';
import 'services/performance_monitor.dart';
import 'services/picked_file_reader_native.dart'
    if (dart.library.js_interop) 'services/picked_file_reader_web.dart';
import 'services/platform_runtime_native.dart'
    if (dart.library.js_interop) 'services/platform_runtime_web.dart';
import 'services/todoist_import_service.dart';
import 'services/update_service.dart';
import 'ui/link_text_editing_controller.dart';
import 'ui/smart_date_text_controller.dart';
import 'ui/todoist_link_text.dart';

part 'ui/settings_view.dart';
part 'ui/data_health_view.dart';
part 'ui/sync_account_card.dart';
part 'ui/trash_view.dart';
part 'ui/task_widgets.dart';
part 'ui/task_editor.dart';

const isPlayDistribution =
    String.fromEnvironment('DISTRIBUTION_CHANNEL') == 'play';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late final Future<_AppRuntime> initialization = _initialize();

  Future<_AppRuntime> _initialize() async {
    final startup = Stopwatch()..start();
    try {
      await DiagnosticLogService.instance.initialize();
    } on Object {
      // La diagnostica non deve mai impedire l'avvio offline.
    }
    final database = AppDatabase();
    final storedDevice = await (database.select(
      database.appSettings,
    )..where((setting) => setting.key.equals('device_id'))).getSingleOrNull();
    var deviceId = storedDevice?.value;
    if (deviceId == null) {
      try {
        const storage = FlutterSecureStorage();
        deviceId = await storage.read(key: 'device_id');
        deviceId ??= const Uuid().v4();
        await storage.write(key: 'device_id', value: deviceId);
      } on Object {
        deviceId = const Uuid().v4();
      }
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: 'device_id', value: deviceId),
          );
    }

    final repository = TaskRepository(database, deviceId: deviceId);
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    SyncService? syncService;
    SupabaseClient? syncClient;
    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseKey,
        authOptions: const FlutterAuthClientOptions(
          localStorage: SecureSupabaseStorage(),
          autoRefreshToken: true,
        ),
      );
      syncClient = Supabase.instance.client;
      syncService = SyncService(database, syncClient)..start();
    }
    await repository.activateScheduled(CivilDate.fromDateTime(DateTime.now()));
    PerformanceMonitor.instance.start();
    startup.stop();
    unawaited(
      PerformanceMonitor.instance.snapshot(
        'startup',
        database,
        durationMs: startup.elapsedMilliseconds,
      ),
    );
    return _AppRuntime(repository, syncClient, syncService);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AppRuntime>(
    future: initialization,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        final runtime = snapshot.requireData;
        return TodoApp(
          repository: runtime.repository,
          syncClient: runtime.syncClient,
          syncService: runtime.syncService,
        );
      }
      if (snapshot.hasError) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text('Impossibile inizializzare l’app'),
                    const SizedBox(height: 8),
                    Text(snapshot.error.runtimeType.toString()),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    },
  );
}

class _AppRuntime {
  const _AppRuntime(this.repository, this.syncClient, this.syncService);
  final TaskRepository repository;
  final SupabaseClient? syncClient;
  final SyncService? syncService;
}

class TodoApp extends StatelessWidget {
  static const brandRed = Color(0xffdb4035);

  const TodoApp({
    required this.repository,
    this.syncClient,
    this.syncService,
    super.key,
  });

  final TaskRepository repository;
  final SupabaseClient? syncClient;
  final SyncService? syncService;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Attività',
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('it')],
    locale: const Locale('it'),
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: TaskShell(
      repository: repository,
      syncClient: syncClient,
      syncService: syncService,
    ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: brandRed,
          brightness: brightness,
        ).copyWith(
          primary: brandRed,
          onPrimary: Colors.white,
          surface: dark ? const Color(0xff1f1f1f) : const Color(0xfffafafa),
          surfaceContainerLow: dark
              ? const Color(0xff242424)
              : const Color(0xfff5f5f5),
          surfaceContainer: dark
              ? const Color(0xff292929)
              : const Color(0xfff0f0f0),
          surfaceContainerHigh: dark
              ? const Color(0xff303030)
              : const Color(0xffe9e9e9),
        );
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}

enum AppSection {
  inbox,
  today,
  upcoming,
  waiting,
  projects,
  completed,
  settings,
}

extension on AppSection {
  String get label => switch (this) {
    AppSection.inbox => 'Inbox',
    AppSection.today => 'Oggi',
    AppSection.upcoming => 'Prossime',
    AppSection.waiting => 'In attesa',
    AppSection.projects => 'Progetti',
    AppSection.completed => 'Completate',
    AppSection.settings => 'Impostazioni',
  };

  IconData get icon => switch (this) {
    AppSection.inbox => Icons.inbox_outlined,
    AppSection.today => Icons.today_outlined,
    AppSection.upcoming => Icons.event_outlined,
    AppSection.waiting => Icons.hourglass_empty,
    AppSection.projects => Icons.folder_outlined,
    AppSection.completed => Icons.check_circle_outline,
    AppSection.settings => Icons.settings_outlined,
  };
}

class TaskShell extends StatefulWidget {
  const TaskShell({
    required this.repository,
    this.syncClient,
    this.syncService,
    super.key,
  });

  final TaskRepository repository;
  final SupabaseClient? syncClient;
  final SyncService? syncService;

  @override
  State<TaskShell> createState() => _TaskShellState();
}

class _TaskShellState extends State<TaskShell> with WidgetsBindingObserver {
  AppSection section = AppSection.today;
  final List<AppSection> sectionHistory = [];
  final Set<String> inboxProjectIds = {};
  String? selectedUpcomingDate;
  String? selectedProjectId;
  final search = TextEditingController();
  late final Stream<List<Task>> activeTasks;
  late final Stream<List<Task>> completedTasks;
  bool backgroundSnapshotTaken = false;
  Timer? updateTimer;
  DateTime? lastUpdateCheck;
  bool checkingForUpdates = false;
  bool appIsForeground = true;
  final Set<String> recentlySyncedTaskIds = {};
  StreamSubscription<Set<String>>? remoteTaskSubscription;
  StreamSubscription<SyncSnapshot>? syncSnapshotSubscription;
  Timer? remoteHighlightTimer;
  Timer? slowSyncTimer;
  SyncSnapshot? currentSyncSnapshot;
  bool showSlowSync = false;
  List<Project> quickAddProjects = const [];
  int lastQuickPriority = 1;
  String? lastQuickProjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInboxProjectIds();
    unawaited(_refreshQuickAddCache());
    activeTasks = widget.repository.watchActive();
    completedTasks = widget.repository.watchCompleted(limit: 200);
    remoteTaskSubscription = widget.syncService?.remoteTaskChanges.listen((
      ids,
    ) {
      if (!mounted) return;
      setState(() {
        recentlySyncedTaskIds
          ..clear()
          ..addAll(ids);
      });
      remoteHighlightTimer?.cancel();
      remoteHighlightTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(recentlySyncedTaskIds.clear);
      });
    });
    currentSyncSnapshot = widget.syncService?.latest;
    syncSnapshotSubscription = widget.syncService?.snapshots.listen((snapshot) {
      slowSyncTimer?.cancel();
      if (snapshot.phase == SyncPhase.syncing) {
        slowSyncTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && currentSyncSnapshot?.phase == SyncPhase.syncing) {
            setState(() => showSlowSync = true);
          }
        });
      } else {
        showSlowSync = false;
      }
      if (mounted) setState(() => currentSyncSnapshot = snapshot);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!isPlayDistribution) await _checkForUpdates();
      await widget.repository.archiveCompletedOlderThan(
        DateTime.now().subtract(const Duration(days: 365)),
      );
      await _showDailyPerformanceReminder();
    });
    if (!isPlayDistribution) {
      updateTimer = Timer.periodic(const Duration(hours: 6), (_) {
        if (appIsForeground) unawaited(_checkForUpdates());
      });
    }
  }

  Future<void> _loadInboxProjectIds() async {
    final projects = await widget.repository.db
        .select(widget.repository.db.projects)
        .get();
    inboxProjectIds
      ..clear()
      ..addAll(
        projects
            .where((project) => project.name.trim().toLowerCase() == 'inbox')
            .map((project) => project.id),
      );
    if (mounted) setState(() {});
  }

  Future<void> _refreshQuickAddCache() async {
    final projects = await widget.repository.db
        .select(widget.repository.db.projects)
        .get();
    final settings =
        await (widget.repository.db.select(widget.repository.db.appSettings)
              ..where(
                (row) => row.key.isIn(const [
                  'last_quick_priority',
                  'last_quick_project',
                ]),
              ))
            .get();
    final values = {for (final setting in settings) setting.key: setting.value};
    final savedPriority = int.tryParse(values['last_quick_priority'] ?? '');
    quickAddProjects = projects
        .where(
          (item) =>
              !item.isArchived && item.name.trim().toLowerCase() != 'inbox',
        )
        .toList();
    lastQuickPriority =
        savedPriority != null && savedPriority >= 1 && savedPriority <= 4
        ? savedPriority
        : 1;
    lastQuickProjectId = values['last_quick_project'];
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
    await showDialog<void>(
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appIsForeground = true;
      backgroundSnapshotTaken = false;
      widget.syncService?.resume();
      unawaited(
        PerformanceMonitor.instance.snapshot('resumed', widget.repository.db),
      );
      if (lastUpdateCheck == null ||
          DateTime.now().difference(lastUpdateCheck!) >=
              const Duration(hours: 6)) {
        if (!isPlayDistribution) unawaited(_checkForUpdates());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      widget.syncService?.pause();
      appIsForeground = false;
      if (!backgroundSnapshotTaken) {
        backgroundSnapshotTaken = true;
        unawaited(PerformanceMonitor.instance.flushFrames());
        unawaited(
          PerformanceMonitor.instance.snapshot(
            'background',
            widget.repository.db,
          ),
        );
      }
    }
  }

  Future<void> _checkForUpdates() async {
    if (isPlayDistribution) {
      await _openPlayStoreListing();
      return;
    }
    if (checkingForUpdates) return;
    checkingForUpdates = true;
    lastUpdateCheck = DateTime.now();
    try {
      final update = await UpdateService().check();
      if (update == null || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aggiornamento disponibile'),
          content: Text(
            'È disponibile la versione ${update.version}. '
            'I dati locali non verranno eliminati.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Più tardi'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _installUpdate(update);
              },
              child: const Text('Aggiorna'),
            ),
          ],
        ),
      );
    } on Object {
      // Offline, timeout o manifest non valido: l'uso locale continua.
    } finally {
      checkingForUpdates = false;
    }
  }

  Future<void> _openPlayStoreListing() async {
    const packageName = 'app.deterministic.todo.deterministic_todo';
    final marketUri = Uri.parse('market://details?id=$packageName');
    final webUri = Uri.https('play.google.com', '/store/apps/details', {
      'id': packageName,
    });
    try {
      if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } on Object {
      // Alcuni dispositivi non espongono lo schema market://.
    }
    final opened = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire Google Play')),
      );
    }
  }

  Future<void> _installUpdate(AvailableUpdate update) async {
    if (!isAndroidPlatform) {
      await launchUrl(update.url, mode: LaunchMode.externalApplication);
      return;
    }
    final ota = OtaUpdate();
    final events = ota.execute(
      update.url.toString(),
      destinationFilename: 'deterministic-todo-${update.version}.apk',
      sha256checksum: update.sha256,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamBuilder<OtaEvent>(
        stream: events,
        builder: (context, snapshot) {
          final event = snapshot.data;
          final progress = event?.status == OtaStatus.DOWNLOADING
              ? double.tryParse(event?.value ?? '')
              : null;
          final failed =
              event != null &&
              {
                OtaStatus.ALREADY_RUNNING_ERROR,
                OtaStatus.INSTALLATION_ERROR,
                OtaStatus.PERMISSION_NOT_GRANTED_ERROR,
                OtaStatus.INTERNAL_ERROR,
                OtaStatus.DOWNLOAD_ERROR,
                OtaStatus.CHECKSUM_ERROR,
              }.contains(event.status);
          final message = switch (event?.status) {
            OtaStatus.DOWNLOADING => 'Download ${event?.value ?? '0'}%',
            OtaStatus.INSTALLING => 'Apro l’installazione Android…',
            OtaStatus.INSTALLATION_DONE => 'Aggiornamento installato',
            OtaStatus.CHECKSUM_ERROR => 'Il file scaricato non è valido.',
            OtaStatus.PERMISSION_NOT_GRANTED_ERROR =>
              'Autorizza l’installazione da questa app nelle impostazioni Android.',
            null => 'Preparo il download…',
            _ when failed => 'Aggiornamento non riuscito. Riprova.',
            _ => 'Aggiornamento in preparazione…',
          };
          return AlertDialog(
            title: Text('Aggiornamento ${update.version}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress == null ? null : progress / 100,
                ),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
            actions: [
              if (failed)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Chiudi'),
                )
              else
                TextButton(
                  onPressed: () async {
                    await ota.cancel();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Annulla'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updateTimer?.cancel();
    remoteHighlightTimer?.cancel();
    slowSyncTimer?.cancel();
    remoteTaskSubscription?.cancel();
    syncSnapshotSubscription?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<bool> _createFrom(
    TextEditingController controller, {
    TextEditingController? notesController,
    int priority = 1,
    String? projectId,
    String? sectionId,
  }) async {
    if (controller.text.trim().isEmpty) return false;
    try {
      final projects = await widget.repository.db
          .select(widget.repository.db.projects)
          .get();
      final metadata = parseQuickAddMetadata(
        controller.text,
        defaultPriority: priority,
        defaultProjectId: projectId,
        projectsByName: {
          for (final project in projects.where((item) => !item.isArchived))
            project.name: project.id,
        },
      );
      final parsed = const QuickAddParser().parse(metadata.text);
      final today = CivilDate.fromDateTime(DateTime.now());
      final notesText = notesController?.text.trim();
      await widget.repository.create(
        linkifyPlainUrls(parsed.title),
        status: parsed.showDate == null
            ? TaskStatus.inbox
            : parsed.showDate!.compareTo(today) <= 0
            ? TaskStatus.available
            : TaskStatus.scheduled,
        showDate: parsed.showDate?.toString(),
        notes: notesText == null || notesText.isEmpty
            ? null
            : linkifyPlainUrls(notesText),
        recurrence: parsed.recurrence,
        priority: metadata.priority,
        projectId: metadata.projectId,
        sectionId: metadata.projectId == projectId ? sectionId : null,
      );
      await _savePreference('last_quick_priority', '${metadata.priority}');
      await _savePreference('last_quick_project', metadata.projectId ?? '');
      lastQuickPriority = metadata.priority;
      lastQuickProjectId = metadata.projectId;
      controller.clear();
      return true;
    } on FormatException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      return false;
    }
  }

  Future<void> _savePreference(String key, String value) => widget.repository.db
      .into(widget.repository.db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  String? _quickAddHelper(String value) {
    if (value.trim().isEmpty) return null;
    try {
      final draft = const QuickAddParser().parse(value);
      final parts = <String>[];
      if (draft.showDate != null) {
        parts.add(
          DateFormat('EEE d MMM', 'it').format(draft.showDate!.asLocalDate),
        );
      }
      if (draft.recurrence != null) {
        parts.add(
          recurrenceSmartLabel(draft.recurrence, draft.showDate?.toString()),
        );
      }
      return parts.isEmpty ? null : parts.join(' · ');
    } on FormatException {
      return null;
    }
  }

  Future<void> _showQuickAddSheet({
    String? projectId,
    String? sectionId,
  }) async {
    final availableProjects = List<Project>.of(quickAddProjects);
    projectId ??= availableProjects.any((item) => item.id == lastQuickProjectId)
        ? lastQuickProjectId
        : null;
    final controller = SmartDateTextController();
    final notesController = TextEditingController();
    final titleFocusNode = FocusNode(debugLabel: 'quick-add-title');
    var keyboardWasVisible = false;
    var stableKeyboardInset = 0.0;
    var closing = false;
    var showNotes = false;
    var priority = lastQuickPriority;
    if (!mounted) return;
    // Refresh in background for the next opening. The current sheet must be
    // mounted immediately, without waiting for SQLite or preferences.
    unawaited(_refreshQuickAddCache());
    // Let Android begin opening the IME in the same frame as the composer.
    titleFocusNode.requestFocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      requestFocus: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration.zero,
        reverseDuration: Duration.zero,
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final currentKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
          if (currentKeyboardInset > 0) {
            keyboardWasVisible = true;
            if (currentKeyboardInset > stableKeyboardInset) {
              stableKeyboardInset = currentKeyboardInset;
            }
          } else if (keyboardWasVisible && !closing) {
            closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            });
          }
          final composerInset = keyboardWasVisible
              ? stableKeyboardInset
              : currentKeyboardInset;
          return Padding(
            key: const ValueKey('mobile-quick-add-keyboard-padding'),
            padding: EdgeInsets.fromLTRB(16, 0, 16, composerInset + 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('mobile-quick-add-field'),
                          controller: controller,
                          focusNode: titleFocusNode,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setSheetState(() {}),
                          onSubmitted: (_) async {
                            if (await _createFrom(
                                  controller,
                                  notesController: notesController,
                                  priority: priority,
                                  projectId: projectId,
                                  sectionId: sectionId,
                                ) &&
                                sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Nuova attività',
                            hintText: 'Cosa devi fare?',
                            helperText: _quickAddHelper(controller.text),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('mobile-quick-add-notes'),
                        tooltip: 'Aggiungi descrizione',
                        onPressed: () => setSheetState(() {
                          showNotes = !showNotes;
                        }),
                        icon: Icon(
                          Icons.notes_outlined,
                          color: showNotes
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      PopupMenuButton<int>(
                        key: const ValueKey('mobile-quick-add-priority'),
                        tooltip: 'Priorità P${5 - priority}',
                        icon: Icon(
                          Icons.circle,
                          size: 20,
                          color: _priorityColor(priority),
                        ),
                        onSelected: (value) =>
                            setSheetState(() => priority = value),
                        itemBuilder: (_) => [
                          for (var raw = 4; raw >= 1; raw--)
                            PopupMenuItem(
                              value: raw,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 18,
                                    color: _priorityColor(raw),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('P${5 - raw}'),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (availableProjects.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: 'Progetto',
                          icon: Icon(
                            projectId == null
                                ? Icons.folder_outlined
                                : Icons.folder,
                            color: projectId == null
                                ? null
                                : Theme.of(context).colorScheme.primary,
                          ),
                          onSelected: (value) => setSheetState(
                            () => projectId = value.isEmpty ? null : value,
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem<String>(
                              value: '',
                              child: Text('Nessun progetto'),
                            ),
                            for (final project in availableProjects)
                              PopupMenuItem<String>(
                                value: project.id,
                                child: Text(project.name),
                              ),
                          ],
                        ),
                      IconButton.filled(
                        key: const ValueKey('mobile-quick-add-submit'),
                        tooltip: 'Aggiungi attività',
                        onPressed: () async {
                          if (await _createFrom(
                                controller,
                                notesController: notesController,
                                priority: priority,
                                projectId: projectId,
                                sectionId: sectionId,
                              ) &&
                              sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                  if (showNotes)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextField(
                        key: const ValueKey('mobile-quick-add-notes-field'),
                        controller: notesController,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Descrizione',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    // The route completes while its exit animation can still own the field for
    // one frame. Dispose after that frame to avoid a controller-after-dispose
    // race on fast submissions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      notesController.dispose();
      titleFocusNode.dispose();
    });
  }

  bool get _canExitFromBack =>
      section == AppSection.today && sectionHistory.isEmpty;

  void _navigateTo(AppSection destination) {
    if (destination == section) return;
    setState(() {
      sectionHistory.add(section);
      if (sectionHistory.length > 20) sectionHistory.removeAt(0);
      section = destination;
    });
  }

  void _handleBack() {
    setState(() {
      if (section == AppSection.projects && selectedProjectId != null) {
        selectedProjectId = null;
      } else if (sectionHistory.isNotEmpty) {
        section = sectionHistory.removeLast();
      } else {
        section = AppSection.today;
      }
    });
  }

  List<Widget> _syncStatusActions() {
    final snapshot = currentSyncSnapshot;
    if (snapshot?.phase == SyncPhase.error ||
        snapshot?.phase == SyncPhase.offline) {
      return [
        IconButton(
          tooltip: snapshot?.phase == SyncPhase.offline
              ? 'Offline'
              : snapshot?.error == null
              ? 'Sincronizzazione non riuscita'
              : 'Sincronizzazione non riuscita · ${snapshot!.error}',
          onPressed: widget.syncService?.sync,
          icon: Icon(
            snapshot?.phase == SyncPhase.offline
                ? Icons.cloud_off_outlined
                : Icons.sync_problem_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ];
    }
    if (showSlowSync && snapshot?.phase == SyncPhase.syncing) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canExitFromBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.slash): _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
      },
      child: Actions(
        actions: {
          _NewIntent: CallbackAction<_NewIntent>(
            onInvoke: (_) => _showQuickAddSheet(),
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) => showSearch<void>(
              context: context,
              delegate: TaskSearchDelegate(widget.repository),
            ),
          ),
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              _handleBack();
              return null;
            },
          ),
        },
        child: StreamBuilder<List<Task>>(
          stream: section == AppSection.completed
              ? completedTasks
              : activeTasks,
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? const [];
            const primarySections = [
              AppSection.today,
              AppSection.upcoming,
              AppSection.projects,
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                final content = Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: desktop ? 960 : 720,
                    child: _content(tasks),
                  ),
                );
                return Scaffold(
                  appBar: AppBar(
                    leadingWidth: desktop ? 80 : null,
                    leading:
                        desktop &&
                            section != AppSection.settings &&
                            section != AppSection.completed
                        ? const SizedBox.shrink()
                        : section == AppSection.settings ||
                              section == AppSection.completed
                        ? IconButton(
                            tooltip: 'Indietro',
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back),
                          )
                        : null,
                    title: Text(section.label),
                    actions: [
                      ..._syncStatusActions(),
                      if (section != AppSection.settings) ...[
                        IconButton(
                          tooltip: 'Cerca (Ctrl/⌘ F)',
                          onPressed: () => showSearch<void>(
                            context: context,
                            delegate: TaskSearchDelegate(widget.repository),
                          ),
                          icon: const Icon(Icons.search),
                        ),
                        IconButton(
                          tooltip: 'Impostazioni',
                          onPressed: () => _navigateTo(AppSection.settings),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ],
                  ),
                  body: desktop
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex: primarySections.contains(section)
                                  ? primarySections.indexOf(section)
                                  : null,
                              onDestinationSelected: (index) =>
                                  _navigateTo(primarySections[index]),
                              labelType: NavigationRailLabelType.all,
                              leading: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: IconButton.filled(
                                  tooltip: 'Nuova attività (Ctrl/⌘ N)',
                                  onPressed: _showQuickAddSheet,
                                  icon: const Icon(Icons.add),
                                ),
                              ),
                              destinations: [
                                for (final item in primarySections)
                                  NavigationRailDestination(
                                    icon: Icon(item.icon),
                                    label: Text(item.label),
                                  ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                  floatingActionButton:
                      !desktop &&
                          section != AppSection.settings &&
                          section != AppSection.projects &&
                          section != AppSection.completed
                      ? FloatingActionButton(
                          tooltip: 'Nuova attività',
                          onPressed: _showQuickAddSheet,
                          child: const Icon(Icons.add),
                        )
                      : null,
                  bottomNavigationBar:
                      desktop ||
                          section == AppSection.settings ||
                          section == AppSection.completed
                      ? null
                      : Center(
                          heightFactor: 1,
                          child: SizedBox(
                            width: 720,
                            child: NavigationBar(
                              selectedIndex: primarySections
                                  .indexOf(section)
                                  .clamp(0, primarySections.length - 1),
                              onDestinationSelected: (index) =>
                                  _navigateTo(primarySections[index]),
                              destinations: [
                                for (final item in primarySections)
                                  NavigationDestination(
                                    icon: Icon(item.icon),
                                    label: item.label,
                                  ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    ),
  );

  Widget _content(List<Task> all) {
    if (section == AppSection.settings) {
      return SettingsView(
        repository: widget.repository,
        syncClient: widget.syncClient,
        syncService: widget.syncService,
        checkForUpdates: _checkForUpdates,
        showCompleted: () => _navigateTo(AppSection.completed),
      );
    }
    if (section == AppSection.projects) return _projectsView(all);
    final today = CivilDate.fromDateTime(DateTime.now()).toString();
    final visible = all.where((task) {
      return switch (section) {
        AppSection.inbox => task.status == TaskStatus.inbox.name,
        AppSection.today =>
          (task.status == TaskStatus.inbox.name &&
                  (task.projectId == null ||
                      inboxProjectIds.contains(task.projectId))) ||
              task.status == TaskStatus.available.name ||
              task.showDate == today,
        AppSection.upcoming =>
          task.status == TaskStatus.scheduled.name &&
              task.showDate != null &&
              task.showDate!.compareTo(today) > 0,
        AppSection.waiting => task.status == TaskStatus.waiting.name,
        AppSection.projects => false,
        AppSection.completed => task.status == TaskStatus.completed.name,
        AppSection.settings => false,
      };
    }).toList();
    visible.sort((a, b) {
      if (section == AppSection.upcoming) {
        final byDate = a.showDate!.compareTo(b.showDate!);
        if (byDate != 0) return byDate;
      }
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return _stableCompare(a, b, today);
    });
    return Column(
      children: [
        if (section == AppSection.upcoming) _futureDateStrip(),
        Expanded(
          child: section == AppSection.upcoming
              ? _upcomingList(visible)
              : visible.isEmpty
              ? const Center(child: Text('Nessuna attività'))
              : ListView.builder(
                  key: PageStorageKey('task-list-${section.name}'),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: visible.length,
                  itemBuilder: (context, index) => TaskTile(
                    key: ValueKey(visible[index].id),
                    task: visible[index],
                    repository: widget.repository,
                    highlightRemote: recentlySyncedTaskIds.contains(
                      visible[index].id,
                    ),
                    dense: section == AppSection.completed,
                    showDateMetadata:
                        section != AppSection.today &&
                        section != AppSection.upcoming,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _projectsView(List<Task> tasks) => StreamBuilder<List<Project>>(
    stream:
        (widget.repository.db.select(widget.repository.db.projects)..orderBy([
              (row) => OrderingTerm(expression: row.position),
              (row) => OrderingTerm(expression: row.name),
            ]))
            .watch(),
    builder: (context, projectSnapshot) => StreamBuilder<List<ProjectSection>>(
      stream: (widget.repository.db.select(
        widget.repository.db.projectSections,
      )..orderBy([(row) => OrderingTerm(expression: row.position)])).watch(),
      builder: (context, sectionSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final sections = sectionSnapshot.data ?? const <ProjectSection>[];
        inboxProjectIds
          ..clear()
          ..addAll(
            projects
                .where(
                  (project) => project.name.trim().toLowerCase() == 'inbox',
                )
                .map((project) => project.id),
          );
        final activeProjects = projects
            .where(
              (item) =>
                  !item.isArchived && item.name.trim().toLowerCase() != 'inbox',
            )
            .toList();
        final selected =
            activeProjects.any((item) => item.id == selectedProjectId)
            ? activeProjects.firstWhere((item) => item.id == selectedProjectId)
            : null;
        if (selected == null) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Text(
                      'I miei progetti',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('create-project'),
                      tooltip: 'Nuovo progetto',
                      onPressed: _addProject,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: activeProjects.isEmpty
                    ? const Center(child: Text('Nessun progetto'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: activeProjects.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 48),
                        itemBuilder: (context, index) {
                          final project = activeProjects[index];
                          return ListTile(
                            key: ValueKey('project-row-${project.id}'),
                            dense: true,
                            leading: Icon(
                              Icons.circle,
                              size: 12,
                              color: _projectColor(project.color),
                            ),
                            title: Text(project.name),
                            trailing: _projectActions(project, activeProjects),
                            onTap: () =>
                                setState(() => selectedProjectId = project.id),
                          );
                        },
                      ),
              ),
            ],
          );
        }
        final projectSections = sections
            .where((item) => item.projectId == selected.id && !item.isArchived)
            .toList();
        final projectTasks = tasks
            .where((item) => item.projectId == selected.id)
            .toList();
        projectTasks.sort((a, b) {
          final byPriority = b.priority.compareTo(a.priority);
          return byPriority != 0 ? byPriority : _stableCompare(a, b, '');
        });
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('back-to-projects'),
                    tooltip: 'Tutti i progetti',
                    onPressed: () => setState(() => selectedProjectId = null),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _projectColor(selected.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aggiungi sezione',
                    onPressed: () => _addSection(selected.id),
                    icon: const Icon(Icons.add_box_outlined),
                  ),
                  _projectActions(selected, activeProjects),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _projectList(selected.id, projectSections, projectTasks),
            ),
          ],
        );
      },
    ),
  );

  Widget _projectList(
    String projectId,
    List<ProjectSection> sections,
    List<Task> tasks,
  ) => ListView(
    key: PageStorageKey('project-list-$projectId'),
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      for (final section in sections)
        ExpansionTile(
          initiallyExpanded: true,
          title: Text(section.name),
          trailing: _sectionActions(section, sections),
          children: [
            for (final task in tasks.where(
              (item) => item.sectionId == section.id,
            ))
              TaskTile(
                key: ValueKey('project-${task.id}'),
                task: task,
                repository: widget.repository,
                highlightRemote: recentlySyncedTaskIds.contains(task.id),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 20),
              title: const Text('Aggiungi'),
              onTap: () => _addProjectTask(projectId, section.id),
            ),
          ],
        ),
      if (tasks.any((item) => item.sectionId == null))
        ExpansionTile(
          initiallyExpanded: true,
          title: const Text('Senza sezione'),
          children: [
            for (final task in tasks.where((item) => item.sectionId == null))
              TaskTile(
                key: ValueKey('project-${task.id}'),
                task: task,
                repository: widget.repository,
                highlightRemote: recentlySyncedTaskIds.contains(task.id),
              ),
          ],
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.add, size: 20),
        title: const Text('Aggiungi'),
        onTap: () => _addProjectTask(projectId, null),
      ),
    ],
  );

  Future<String?> _askName(
    String title,
    String label, {
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  Future<void> _addProject() async {
    final controller = TextEditingController();
    var color = 'green';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo progetto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in const [
                    'red',
                    'orange',
                    'yellow',
                    'green',
                    'blue',
                    'purple',
                    'pink',
                  ])
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: _projectColor(value),
                      ),
                      label: const SizedBox.shrink(),
                      selected: color == value,
                      onSelected: (_) => setDialogState(() => color = value),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (controller.text, color)),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.trim().isEmpty) return;
    final id = await widget.repository.createProject(
      result.$1,
      color: result.$2,
    );
    if (mounted) setState(() => selectedProjectId = id);
    await widget.syncService?.sync();
  }

  Future<void> _addSection(String projectId) async {
    final name = await _askName('Nuova sezione', 'Nome');
    if (name == null) return;
    await widget.repository.createProjectSection(projectId, name);
    await widget.syncService?.sync();
  }

  Widget _projectActions(Project project, List<Project> projects) {
    final index = projects.indexWhere((item) => item.id == project.id);
    return PopupMenuButton<String>(
      key: ValueKey('project-actions-${project.id}'),
      tooltip: 'Azioni progetto',
      onSelected: (action) =>
          _handleProjectAction(action, project, projects, index),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
        PopupMenuItem(
          value: 'up',
          enabled: index > 0,
          child: const Text('Sposta su'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: index >= 0 && index < projects.length - 1,
          child: const Text('Sposta giù'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Elimina')),
      ],
    );
  }

  Future<void> _handleProjectAction(
    String action,
    Project project,
    List<Project> projects,
    int index,
  ) async {
    if (action == 'rename') {
      final name = await _askName(
        'Rinomina progetto',
        'Nome',
        initialValue: project.name,
      );
      if (name == null) return;
      await widget.repository.updateProject(project, name: name);
    } else if (action == 'up' && index > 0) {
      await widget.repository.swapProjects(project, projects[index - 1]);
    } else if (action == 'down' && index < projects.length - 1) {
      await widget.repository.swapProjects(project, projects[index + 1]);
    } else if (action == 'delete') {
      await widget.repository.updateProject(project, isArchived: true);
      if (mounted && selectedProjectId == project.id) {
        setState(() => selectedProjectId = null);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Progetto “${project.name}” eliminato'),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () async {
              final current = await (widget.repository.db.select(
                widget.repository.db.projects,
              )..where((row) => row.id.equals(project.id))).getSingle();
              await widget.repository.updateProject(current, isArchived: false);
              await widget.syncService?.sync();
            },
          ),
        ),
      );
    }
    await widget.syncService?.sync();
  }

  Widget _sectionActions(
    ProjectSection section,
    List<ProjectSection> sections,
  ) {
    final index = sections.indexWhere((item) => item.id == section.id);
    return PopupMenuButton<String>(
      key: ValueKey('section-actions-${section.id}'),
      tooltip: 'Azioni sezione',
      onSelected: (action) =>
          _handleSectionAction(action, section, sections, index),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
        PopupMenuItem(
          value: 'up',
          enabled: index > 0,
          child: const Text('Sposta su'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: index >= 0 && index < sections.length - 1,
          child: const Text('Sposta giù'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Elimina')),
      ],
    );
  }

  Future<void> _handleSectionAction(
    String action,
    ProjectSection section,
    List<ProjectSection> sections,
    int index,
  ) async {
    if (action == 'rename') {
      final name = await _askName(
        'Rinomina sezione',
        'Nome',
        initialValue: section.name,
      );
      if (name == null) return;
      await widget.repository.updateProjectSection(section, name: name);
    } else if (action == 'up' && index > 0) {
      await widget.repository.swapProjectSections(section, sections[index - 1]);
    } else if (action == 'down' && index < sections.length - 1) {
      await widget.repository.swapProjectSections(section, sections[index + 1]);
    } else if (action == 'delete') {
      await widget.repository.updateProjectSection(section, isArchived: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Sezione “${section.name}” eliminata'),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () async {
              final current = await (widget.repository.db.select(
                widget.repository.db.projectSections,
              )..where((row) => row.id.equals(section.id))).getSingle();
              await widget.repository.updateProjectSection(
                current,
                isArchived: false,
              );
              await widget.syncService?.sync();
            },
          ),
        ),
      );
    }
    await widget.syncService?.sync();
  }

  Future<void> _addProjectTask(String projectId, String? sectionId) async {
    await _showQuickAddSheet(projectId: projectId, sectionId: sectionId);
  }

  Color _projectColor(String? value) => switch (value) {
    'red' || 'berry_red' => Colors.red,
    'orange' => Colors.orange,
    'yellow' => Colors.amber,
    'blue' || 'sky_blue' => Colors.blue,
    'purple' || 'violet' => Colors.purple,
    'pink' || 'magenta' => Colors.pink,
    'green' || 'lime_green' => Colors.green,
    _ => Colors.grey,
  };

  Widget _futureDateStrip() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 2),
        child: TextButton.icon(
          key: const ValueKey('jump-to-future-date'),
          onPressed: _pickFutureDate,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text(
            selectedUpcomingDate == null
                ? 'Vai a data'
                : DateFormat(
                    'd MMM yyyy',
                    'it',
                  ).format(CivilDate.parse(selectedUpcomingDate!).asLocalDate),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFutureDate() async {
    final now = DateTime.now();
    final initial = selectedUpcomingDate == null
        ? now.add(const Duration(days: 1))
        : CivilDate.parse(selectedUpcomingDate!).asLocalDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day + 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'Vai rapidamente a una data',
    );
    if (picked != null && mounted) {
      setState(
        () => selectedUpcomingDate = CivilDate.fromDateTime(picked).toString(),
      );
    }
  }

  Widget _upcomingList(List<Task> tasks) {
    final grouped = <String, List<Task>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(task.showDate!, () => []).add(task);
    }
    final today = CivilDate.fromDateTime(DateTime.now());
    final start = selectedUpcomingDate == null
        ? today.addDays(1)
        : CivilDate.parse(selectedUpcomingDate!);
    final lastDate = CivilDate(today.year + 10, 12, 31);
    final dayCount = lastDate.asLocalDate.difference(start.asLocalDate).inDays;
    return ListView.builder(
      key: PageStorageKey('upcoming-$selectedUpcomingDate'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: dayCount + 1,
      itemBuilder: (context, index) {
        final date = start.addDays(index);
        final dateTasks = grouped[date.toString()] ?? const <Task>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
              child: Text(
                _friendlyDate(date.toString()),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (dateTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Nessuna attività',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final task in dateTasks)
                TaskTile(
                  key: ValueKey(task.id),
                  task: task,
                  repository: widget.repository,
                  showDateMetadata: false,
                  highlightRemote: recentlySyncedTaskIds.contains(task.id),
                ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  String _friendlyDate(String value) {
    final date = CivilDate.parse(value).asLocalDate;
    final label = DateFormat('EEEE d MMMM', 'it').format(date);
    return label[0].toUpperCase() + label.substring(1);
  }
}

int _stableCompare(Task a, Task b, String today) {
  int group(Task task) {
    if (task.showDate == today) return 0;
    return 1;
  }

  final byGroup = group(a).compareTo(group(b));
  if (byGroup != 0) return byGroup;
  final byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) return byPosition;
  final byCreation = a.createdAt.compareTo(b.createdAt);
  return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
}

class TaskSearchDelegate extends SearchDelegate<void> {
  TaskSearchDelegate(this.repository)
    : _projects = repository.db.select(repository.db.projects).get();
  final TaskRepository repository;
  final Future<List<Project>> _projects;
  final Set<_TaskSearchFilter> _filters = {};

  @override
  String get searchFieldLabel => 'Cerca titolo e note';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) => FutureBuilder<List<Project>>(
    future: _projects,
    builder: (context, projectSnapshot) => StreamBuilder<List<Task>>(
      stream: repository.watchAll(),
      builder: (context, snapshot) {
        final needle = query.trim().toLowerCase();
        final projectNames = {
          for (final project in projectSnapshot.data ?? const <Project>[])
            project.id: project.name.toLowerCase(),
        };
        final today = CivilDate.fromDateTime(DateTime.now()).toString();
        final results = (snapshot.data ?? const <Task>[]).where((task) {
          final matchesText =
              needle.isEmpty ||
              task.title.toLowerCase().contains(needle) ||
              (task.notes?.toLowerCase().contains(needle) ?? false) ||
              (projectNames[task.projectId]?.contains(needle) ?? false);
          if (!matchesText) return false;
          if (_filters.contains(_TaskSearchFilter.today) &&
              task.showDate != today) {
            return false;
          }
          if (_filters.contains(_TaskSearchFilter.undated) &&
              task.showDate != null) {
            return false;
          }
          if (_filters.contains(_TaskSearchFilter.recurring) &&
              task.recurrence == null) {
            return false;
          }
          if (_filters.contains(_TaskSearchFilter.highPriority) &&
              task.priority < 3) {
            return false;
          }
          return true;
        }).toList();
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  for (final filter in _TaskSearchFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(filter.label),
                        selected: _filters.contains(filter),
                        onSelected: (selected) {
                          selected
                              ? _filters.add(filter)
                              : _filters.remove(filter);
                          showSuggestions(context);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final task in results)
                    TaskTile(task: task, repository: repository),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

enum _TaskSearchFilter {
  today('Oggi'),
  undated('Senza data'),
  recurring('Ricorrenti'),
  highPriority('Priorità alta');

  const _TaskSearchFilter(this.label);
  final String label;
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _BackIntent extends Intent {
  const _BackIntent();
}
