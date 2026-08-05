import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'data/local/database.dart';
import 'data/sync/secure_supabase_storage.dart';
import 'data/sync/sync_service.dart';
import 'data/task_repository.dart';
import 'domain/quick_add_parser.dart';
import 'domain/task.dart';
import 'services/calendar_service.dart';
import 'services/diagnostic_log_service.dart';
import 'services/export_service.dart';
import 'services/performance_monitor.dart';
import 'services/todoist_import_service.dart';
import 'services/update_service.dart';
import 'ui/link_text_editing_controller.dart';
import 'ui/smart_date_text_controller.dart';
import 'ui/todoist_link_text.dart';

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

  ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorSchemeSeed: const Color(0xff356859),
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
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
  final quickAdd = SmartDateTextController();
  final search = TextEditingController();
  final quickFocus = FocusNode();
  late final Stream<List<Task>> activeTasks;
  late final Stream<List<Task>> completedTasks;
  bool backgroundSnapshotTaken = false;
  Timer? updateTimer;
  DateTime? lastUpdateCheck;
  bool checkingForUpdates = false;
  bool appIsForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInboxProjectIds();
    activeTasks = widget.repository.watchActive();
    completedTasks = widget.repository.watchCompleted(limit: 200);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForUpdates();
      await widget.repository.archiveCompletedOlderThan(
        DateTime.now().subtract(const Duration(days: 365)),
      );
      await _showDailyPerformanceReminder();
    });
    updateTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (appIsForeground) unawaited(_checkForUpdates());
    });
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
              final file = await DiagnosticLogService.instance.exportFile();
              if (file != null) {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(file.path)],
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
        unawaited(_checkForUpdates());
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

  Future<void> _installUpdate(AvailableUpdate update) async {
    if (!Platform.isAndroid) {
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
    quickAdd.dispose();
    search.dispose();
    quickFocus.dispose();
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
      final parsed = const QuickAddParser().parse(controller.text);
      final today = CivilDate.fromDateTime(DateTime.now());
      await widget.repository.create(
        parsed.title,
        status: parsed.showDate == null
            ? TaskStatus.inbox
            : parsed.showDate!.compareTo(today) <= 0
            ? TaskStatus.available
            : TaskStatus.scheduled,
        showDate: parsed.showDate?.toString(),
        notes: notesController?.text.trim().isEmpty == true
            ? null
            : notesController?.text.trim(),
        recurrence: parsed.recurrence,
        priority: priority,
        projectId: projectId,
        sectionId: sectionId,
      );
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

  Future<void> _create() async {
    await _createFrom(quickAdd);
  }

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
    final controller = SmartDateTextController();
    final notesController = TextEditingController();
    var keyboardWasVisible = false;
    var closing = false;
    var showNotes = false;
    var priority = 1;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 30),
        reverseDuration: Duration(milliseconds: 20),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
          if (keyboardInset > 0) {
            keyboardWasVisible = true;
          } else if (keyboardWasVisible && !closing) {
            closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            });
          }
          return AnimatedPadding(
            duration: Duration.zero,
            padding: EdgeInsets.fromLTRB(16, 0, 16, keyboardInset + 12),
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
                          autofocus: true,
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
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchIntent(),
      },
      child: Actions(
        actions: {
          _NewIntent: CallbackAction<_NewIntent>(
            onInvoke: (_) => quickFocus.requestFocus(),
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) => showSearch<void>(
              context: context,
              delegate: TaskSearchDelegate(widget.repository),
            ),
          ),
        },
        child: StreamBuilder<List<Task>>(
          stream: section == AppSection.completed
              ? completedTasks
              : activeTasks,
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? const [];
            return LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 720;
                final content = _content(tasks);
                const desktopSections = [
                  AppSection.inbox,
                  AppSection.today,
                  AppSection.upcoming,
                  AppSection.waiting,
                  AppSection.projects,
                  AppSection.settings,
                ];
                return Scaffold(
                  appBar: desktop
                      ? null
                      : AppBar(
                          leading:
                              section == AppSection.settings ||
                                  section == AppSection.completed
                              ? IconButton(
                                  tooltip: 'Indietro',
                                  onPressed: _handleBack,
                                  icon: const Icon(Icons.arrow_back),
                                )
                              : null,
                          title: Text(section.label),
                          actions: [
                            if (section != AppSection.settings) ...[
                              IconButton(
                                tooltip: 'Cerca',
                                onPressed: () => showSearch<void>(
                                  context: context,
                                  delegate: TaskSearchDelegate(
                                    widget.repository,
                                  ),
                                ),
                                icon: const Icon(Icons.search),
                              ),
                              IconButton(
                                tooltip: 'Impostazioni',
                                onPressed: () =>
                                    _navigateTo(AppSection.settings),
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ],
                          ],
                        ),
                  body: desktop
                      ? Row(
                          children: [
                            NavigationRail(
                              extended: constraints.maxWidth >= 1000,
                              selectedIndex: desktopSections.contains(section)
                                  ? desktopSections.indexOf(section)
                                  : desktopSections.indexOf(
                                      AppSection.settings,
                                    ),
                              onDestinationSelected: (index) =>
                                  _navigateTo(desktopSections[index]),
                              leading: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Icon(Icons.check_box_outlined, size: 32),
                              ),
                              destinations: [
                                for (final item in desktopSections)
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
                  bottomNavigationBar: desktop
                      ? null
                      : section == AppSection.settings ||
                            section == AppSection.completed
                      ? null
                      : Builder(
                          builder: (context) {
                            const mobileSections = [
                              AppSection.today,
                              AppSection.upcoming,
                              AppSection.projects,
                            ];
                            return NavigationBar(
                              selectedIndex: mobileSections
                                  .indexOf(section)
                                  .clamp(0, mobileSections.length - 1),
                              onDestinationSelected: (index) =>
                                  _navigateTo(mobileSections[index]),
                              destinations: [
                                for (final item in mobileSections)
                                  NavigationDestination(
                                    icon: Icon(item.icon),
                                    label: item.label,
                                  ),
                              ],
                            );
                          },
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
        if (MediaQuery.sizeOf(context).width >= 720)
          ListTile(
            title: Text(
              section.label,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            trailing: IconButton(
              tooltip: 'Cerca (Ctrl/⌘ F)',
              onPressed: () => showSearch<void>(
                context: context,
                delegate: TaskSearchDelegate(widget.repository),
              ),
              icon: const Icon(Icons.search),
            ),
          ),
        if (MediaQuery.sizeOf(context).width >= 720)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: quickAdd,
              focusNode: quickFocus,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                labelText: 'Nuova attività',
                helperText: _quickAddHelper(quickAdd.text),
                prefixIcon: const Icon(Icons.add),
                suffixIcon: IconButton(
                  tooltip: 'Aggiungi',
                  onPressed: _create,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
        if (section == AppSection.upcoming) _futureDateStrip(),
        Expanded(
          child: section == AppSection.upcoming
              ? _upcomingList(visible)
              : visible.isEmpty
              ? const Center(child: Text('Nessuna attività'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: visible.length,
                  itemBuilder: (context, index) => TaskTile(
                    key: ValueKey(visible[index].id),
                    task: visible[index],
                    repository: widget.repository,
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

Color _priorityColor(int rawPriority) => switch (rawPriority) {
  4 => Colors.red,
  3 => Colors.orange,
  2 => Colors.blue,
  _ => Colors.grey,
};

class TaskTile extends StatefulWidget {
  const TaskTile({
    required this.task,
    required this.repository,
    this.showDateMetadata = true,
    this.dense = false,
    super.key,
  });

  final Task task;
  final TaskRepository repository;
  final bool showDateMetadata;
  final bool dense;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool confirmingCompletion = false;
  bool leavingAfterCompletion = false;

  Future<void> _setCompleted(bool completed) async {
    if (!completed) {
      await widget.repository.setCompleted(widget.task, false);
      return;
    }
    setState(() => confirmingCompletion = true);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => leavingAfterCompletion = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await widget.repository.setCompleted(widget.task, true);
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    key: ValueKey('completion-slide-${widget.task.id}'),
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeInCubic,
    offset: leavingAfterCompletion ? const Offset(0.12, 0) : Offset.zero,
    child: AnimatedOpacity(
      key: ValueKey('completion-opacity-${widget.task.id}'),
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeInCubic,
      opacity: leavingAfterCompletion ? 0 : 1,
      child: Dismissible(
        key: ValueKey('dismiss-${widget.task.id}'),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {DismissDirection.endToStart: 0.62},
        movementDuration: const Duration(milliseconds: 110),
        resizeDuration: const Duration(milliseconds: 100),
        background: const SizedBox.shrink(),
        secondaryBackground: Container(
          color: Theme.of(context).colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        onDismissed: (_) async {
          final messenger = ScaffoldMessenger.of(context);
          await widget.repository.softDelete(widget.task);
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Spostata nel cestino'),
              action: SnackBarAction(
                label: 'Annulla',
                onPressed: () => widget.repository.restore(widget.task),
              ),
            ),
          );
        },
        child: AnimatedContainer(
          key: ValueKey('task-surface-${widget.task.id}'),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: confirmingCompletion
                ? Colors.green.withValues(alpha: 0.10)
                : widget.task.priority == 1
                ? Colors.transparent
                : _priorityColor(widget.task.priority).withValues(alpha: 0.035),
            border: widget.task.priority == 1
                ? null
                : Border(
                    left: BorderSide(
                      color: _priorityColor(widget.task.priority),
                      width: 3,
                    ),
                  ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              dense: widget.dense,
              visualDensity: widget.dense
                  ? const VisualDensity(vertical: -2)
                  : null,
              leading: AnimatedScale(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                scale: confirmingCompletion ? 1.22 : 1,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: confirmingCompletion
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('completed-check'),
                          color: Colors.green,
                          size: 30,
                        )
                      : Checkbox(
                          key: const ValueKey('task-checkbox'),
                          value:
                              widget.task.status == TaskStatus.completed.name,
                          onChanged: (value) => _setCompleted(value ?? false),
                          activeColor: Colors.green,
                          side: BorderSide(
                            color: _priorityColor(widget.task.priority),
                            width: widget.task.priority == 1 ? 1.5 : 2.5,
                          ),
                        ),
                ),
              ),
              title: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: DefaultTextStyle.of(context).style.copyWith(
                  color: confirmingCompletion ? Colors.green.shade700 : null,
                  decoration: confirmingCompletion
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
                child: TodoistLinkText(widget.task.title),
              ),
              subtitle: _subtitle(widget.task),
              onTap: confirmingCompletion ? null : _showEditor,
            ),
          ),
        ),
      ),
    ),
  );

  Widget? _subtitle(Task task) {
    final metadata = [
      if (widget.showDateMetadata && task.showDate != null)
        DateFormat(
          'd MMM',
          'it',
        ).format(CivilDate.parse(task.showDate!).asLocalDate),
      if (task.recurrence != null)
        '↻ ${recurrenceSmartLabel(task.recurrence, task.showDate)}',
    ];
    final notes = task.notes?.trim();
    if ((notes == null || notes.isEmpty) && metadata.isEmpty) return null;
    final secondaryStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notes != null && notes.isNotEmpty)
          TodoistLinkText(
            notes,
            style: secondaryStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (metadata.isNotEmpty)
          Text(metadata.join(' · '), style: secondaryStyle),
      ],
    );
  }

  Future<void> _showEditor() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 45),
      reverseDuration: Duration(milliseconds: 25),
    ),
    builder: (_) =>
        TaskEditor(task: widget.task, repository: widget.repository),
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({required this.task, required this.repository, super.key});

  final Task task;
  final TaskRepository repository;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final LinkTextEditingController title =
      LinkTextEditingController.fromMarkdown(widget.task.title);
  late final LinkTextEditingController notes =
      LinkTextEditingController.fromMarkdown(widget.task.notes);
  late final TextEditingController showDate = TextEditingController(
    text: widget.task.showDate,
  );
  late String recurrence = widget.task.recurrence ?? 'none';
  late String? projectId = widget.task.projectId;
  late String? projectSectionId = widget.task.sectionId;
  late int priority = widget.task.priority;

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    showDate.dispose();
    super.dispose();
  }

  Future<Task> _save() async {
    await widget.repository.updateDetails(
      widget.task,
      title: title.toMarkdown(),
      notes: notes.text.trim().isEmpty ? null : notes.toMarkdown().trim(),
      showDate: showDate.text.trim().isEmpty
          ? null
          : CivilDate.parse(showDate.text.trim()).toString(),
      recurrence: recurrence == 'none' ? null : recurrence,
      priority: priority,
      projectId: projectId,
      sectionId: projectSectionId,
      updateProject: true,
    );
    var refreshed = await (widget.repository.db.select(
      widget.repository.db.tasks,
    )..where((row) => row.id.equals(widget.task.id))).getSingle();
    final plannedDate = showDate.text.trim().isEmpty
        ? null
        : CivilDate.parse(showDate.text.trim());
    final today = CivilDate.fromDateTime(DateTime.now());
    final derivedStatus = plannedDate == null
        ? TaskStatus.inbox
        : plannedDate.compareTo(today) <= 0
        ? TaskStatus.available
        : TaskStatus.scheduled;
    if (derivedStatus.name != refreshed.status) {
      await widget.repository.move(refreshed, derivedStatus);
      refreshed = await (widget.repository.db.select(
        widget.repository.db.tasks,
      )..where((row) => row.id.equals(widget.task.id))).getSingle();
    }
    return refreshed;
  }

  Future<void> _saveAndExportToCalendar() async {
    try {
      final saved = await _save();
      final result = await CalendarService(
        widget.repository.db,
      ).exportTask(saved);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Aggiunta a ${result.calendarName}')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message.toString()
          : 'Impossibile aggiungere al calendario.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 40),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const ValueKey('task-editor-title'),
                      controller: title,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Cosa devi fare?',
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        suffixIcon: PopupMenuButton<String>(
                          tooltip: 'Link nel titolo',
                          icon: const Icon(Icons.link),
                          onSelected: (value) {
                            if (value == 'add') {
                              _addLinkToSelection(title);
                            } else if (!title.removeSelectedLink()) {
                              _showSelectLinkedTextMessage();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'add',
                              child: Text('Aggiungi link'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Togli link'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _compactActions(),
                    ExpansionTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      leading: const Icon(Icons.tune),
                      title: const Text('Altri dettagli'),
                      children: [
                        TextField(
                          controller: notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Note'),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () => _addLinkToSelection(notes),
                                icon: const Icon(Icons.link, size: 18),
                                label: const Text('Aggiungi link'),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  if (!notes.removeSelectedLink()) {
                                    _showSelectLinkedTextMessage();
                                  }
                                },
                                icon: const Icon(Icons.link_off, size: 18),
                                label: const Text('Togli link'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _projectFields(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('task-editor-save'),
                  onPressed: () async {
                    await _save();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Salva'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _compactActions() {
    const basic = <String>[
      'none',
      'calendar:day:1',
      'calendar:week:1',
      'calendar:month:1',
      'afterCompletion:day:1',
      'afterCompletion:week:1',
      'afterCompletion:month:1',
    ];
    final values = basic.contains(recurrence)
        ? basic
        : <String>[recurrence, ...basic];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(_compactDateLabel()),
            onPressed: _pickShowDate,
          ),
          if (showDate.text.isNotEmpty)
            IconButton(
              tooltip: 'Rimuovi data',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(showDate.clear),
              icon: const Icon(Icons.close, size: 18),
            ),
          PopupMenuButton<int>(
            tooltip: 'Priorità P${5 - priority}',
            icon: Icon(Icons.circle, color: _priorityColor(priority), size: 20),
            onSelected: (value) => setState(() => priority = value),
            itemBuilder: (context) => [
              for (var raw = 4; raw >= 1; raw--)
                PopupMenuItem(
                  value: raw,
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: _priorityColor(raw), size: 18),
                      const SizedBox(width: 10),
                      Text('P${5 - raw}'),
                    ],
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Ripetizione',
            icon: Icon(
              Icons.repeat,
              color: recurrence == 'none'
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
            ),
            onSelected: (value) => setState(() => recurrence = value),
            itemBuilder: (context) => [
              for (final value in values)
                PopupMenuItem(
                  value: value,
                  child: Text(
                    value == 'none'
                        ? 'Mai'
                        : recurrenceSmartLabel(value, showDate.text),
                  ),
                ),
            ],
          ),
          if (Platform.isAndroid)
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'calendar') _saveAndExportToCalendar();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'calendar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_available_outlined),
                    title: Text('Aggiungi a Google Calendar'),
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Chiudi',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }

  String _compactDateLabel() {
    if (showDate.text.isEmpty) return 'Data';
    try {
      return DateFormat(
        'd MMM',
        'it',
      ).format(CivilDate.parse(showDate.text).asLocalDate);
    } on FormatException {
      return 'Data';
    }
  }

  Future<void> _pickShowDate() async {
    final current = showDate.text.isEmpty
        ? DateTime.now()
        : CivilDate.parse(showDate.text).asLocalDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => showDate.text = CivilDate.fromDateTime(picked).toString());
    }
  }

  void _showSelectLinkedTextMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seleziona il testo collegato.')),
    );
  }

  Future<void> _addLinkToSelection(LinkTextEditingController controller) async {
    if (controller.selectedText?.trim().isEmpty ?? true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prima seleziona il testo da collegare.')),
      );
      return;
    }
    final url = TextEditingController(text: 'https://');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi link'),
        content: TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Indirizzo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, url.text),
            child: const Text('Collega'),
          ),
        ],
      ),
    );
    url.dispose();
    if (value == null || !mounted) return;
    if (!controller.addLink(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un indirizzo valido.')),
      );
    } else {
      setState(() {});
    }
  }

  Widget _projectFields() => StreamBuilder<List<Project>>(
    stream: widget.repository.db.select(widget.repository.db.projects).watch(),
    builder: (context, projectSnapshot) => StreamBuilder<List<ProjectSection>>(
      stream: widget.repository.db
          .select(widget.repository.db.projectSections)
          .watch(),
      builder: (context, sectionSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final sections = (sectionSnapshot.data ?? const <ProjectSection>[])
            .where((item) => item.projectId == projectId && !item.isArchived)
            .toList();
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: projects.any((item) => item.id == projectId)
                    ? projectId
                    : null,
                decoration: const InputDecoration(labelText: 'Progetto'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuno')),
                  for (final project in projects.where(
                    (item) => !item.isArchived,
                  ))
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) => setState(() {
                  projectId = value;
                  projectSectionId = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue:
                    sections.any((item) => item.id == projectSectionId)
                    ? projectSectionId
                    : null,
                decoration: const InputDecoration(labelText: 'Sezione'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuna')),
                  for (final section in sections)
                    DropdownMenuItem(
                      value: section.id,
                      child: Text(section.name),
                    ),
                ],
                onChanged: projectId == null
                    ? null
                    : (value) => setState(() => projectSectionId = value),
              ),
            ),
          ],
        );
      },
    ),
  );
}

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
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/attivita.${json ? 'json' : 'csv'}');
    await file.writeAsString(content, flush: true);
    if (context.mounted) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], title: 'Esporta attività'),
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
    final source = bytes == null
        ? await File(picked.files.single.path!).readAsString()
        : String.fromCharCodes(bytes);
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
          const SnackBar(content: Text('Importazione completata')),
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
      final source = bytes == null
          ? await File(picked.files.single.path!).readAsString()
          : String.fromCharCodes(bytes);
      const service = TodoistImportService();
      final preview = service.preview(source);
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
        plan: service.plan(source),
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Import completato: ${result.addedTasks} nuove, '
              '${result.updatedTasks} aggiornate, '
              '${result.removedTasks} rimosse; '
              '${result.addedProjects} progetti e '
              '${result.addedSections} sezioni aggiunti.',
            ),
          ),
        );
      }
    } on FormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on PostgrestException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Prima esegui in Supabase la migrazione '
            '202608040002_todoist_import.sql. Nessun dato è stato importato.',
          ),
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Import Todoist non riuscito: nessun dato modificato.'),
        ),
      );
    }
  }

  Future<void> _exportDiagnostics(BuildContext context) async {
    final file = await DiagnosticLogService.instance.exportFile();
    if (file == null || !context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dati locali cancellati')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
    children: [
      if (MediaQuery.sizeOf(context).width >= 720)
        const ListTile(
          title: Text('Impostazioni', style: TextStyle(fontSize: 28)),
        ),
      SyncAccountCard(client: syncClient, syncService: syncService),
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) => ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('Controlla aggiornamenti'),
          subtitle: Text(
            snapshot.hasData
                ? 'Versione installata: ${snapshot.requireData.version} '
                      '(${snapshot.requireData.buildNumber})'
                : 'Verifica la release pubblica più recente',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await checkForUpdates();
            if (context.mounted) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Controllo completato')),
              );
            }
          },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: const Text('Attività completate'),
        trailing: const Icon(Icons.chevron_right),
        onTap: showCompleted,
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

class SyncAccountCard extends StatefulWidget {
  const SyncAccountCard({this.client, this.syncService, super.key});

  final SupabaseClient? client;
  final SyncService? syncService;

  @override
  State<SyncAccountCard> createState() => _SyncAccountCardState();
}

class _SyncAccountCardState extends State<SyncAccountCard> {
  final email = TextEditingController();
  final password = TextEditingController();
  StreamSubscription<AuthState>? authSubscription;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    authSubscription = widget.client?.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _connect({required bool create}) async {
    final client = widget.client;
    if (client == null || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (create) {
        final response = await client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
        );
        message = response.session == null
            ? 'Controlla l’email una sola volta, poi premi Collega.'
            : 'Collegamento permanente attivo.';
      } else {
        await client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        await widget.syncService?.sync();
        message = 'Collegamento permanente attivo.';
      }
      password.clear();
    } on AuthException catch (error) {
      message = error.message;
    } on Object {
      message = 'Collegamento non riuscito. Controlla la connessione.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Sincronizzazione non configurata'),
        subtitle: Text(
          'Servono Project URL e chiave pubblica Supabase nella build.',
        ),
      );
    }
    final user = client.auth.currentUser;
    if (user != null) {
      final service = widget.syncService;
      return StreamBuilder<SyncSnapshot>(
        stream: service?.snapshots,
        initialData: service?.latest,
        builder: (context, snapshot) {
          final sync = snapshot.data;
          return ListTile(
            leading: Icon(
              sync?.phase == SyncPhase.error
                  ? Icons.sync_problem_outlined
                  : Icons.cloud_done_outlined,
            ),
            title: Text(_syncLabel(sync)),
            trailing: PopupMenuButton<String>(
              tooltip: 'Gestisci collegamento',
              onSelected: (value) async {
                if (value == 'sync') await service?.sync();
                if (value == 'disconnect') await client.auth.signOut();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sync', child: Text('Sincronizza ora')),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Scollega questo dispositivo'),
                ),
              ],
            ),
          );
        },
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Collega i dispositivi una sola volta',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Usa lo stesso account personale su ogni dispositivo. '
              'Non sarà richiesto un accesso quotidiano.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => _connect(create: true),
                  child: const Text('Crea account'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : () => _connect(create: false),
                  child: Text(busy ? 'Collego…' : 'Collega'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _syncLabel(SyncSnapshot? snapshot) => switch (snapshot?.phase) {
    SyncPhase.syncing => 'Sincronizzazione (${snapshot!.pending})…',
    SyncPhase.current =>
      snapshot!.lastSuccess == null
          ? 'Sincronizzato'
          : 'Sincronizzato · ${DateFormat('HH:mm').format(snapshot.lastSuccess!.toLocal())}',
    SyncPhase.error => 'Errore di sincronizzazione',
    SyncPhase.offline => 'Offline',
    SyncPhase.disabled || null => 'Collegato',
  };
}

class TaskSearchDelegate extends SearchDelegate<void> {
  TaskSearchDelegate(this.repository);
  final TaskRepository repository;

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
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() => StreamBuilder<List<Task>>(
    stream: repository.watchAll(),
    builder: (context, snapshot) {
      final needle = query.trim().toLowerCase();
      final results = (snapshot.data ?? const <Task>[])
          .where(
            (task) =>
                task.title.toLowerCase().contains(needle) ||
                (task.notes?.toLowerCase().contains(needle) ?? false),
          )
          .toList();
      return ListView(
        children: [
          for (final task in results)
            TaskTile(task: task, repository: repository),
        ],
      );
    },
  );
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}
