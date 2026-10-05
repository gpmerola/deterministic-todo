import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, QueryRow;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'background/agenda_background.dart';
import 'data/editor_drafts.dart';
import 'data/local/database.dart';
import 'data/sync/secure_supabase_storage.dart';
import 'data/sync/sync_service.dart';
import 'data/task_repository.dart';
import 'domain/agenda.dart';
import 'domain/ai_capture.dart';
import 'domain/link_syntax.dart';
import 'domain/quick_add_metadata.dart';
import 'domain/quick_add_parser.dart';
import 'domain/task.dart';
import 'domain/task_planning.dart';
import 'services/agenda_phone_sync.dart';
import 'services/agenda_service.dart';
import 'services/agenda_tasks.dart';
import 'services/agenda_web_service.dart';
import 'services/ai_settings.dart';
import 'services/calendar_service.dart';
import 'services/diagnostic_log_service.dart';
import 'services/export_service.dart';
import 'services/performance_monitor.dart';
import 'services/picked_file_reader_native.dart'
    if (dart.library.js_interop) 'services/picked_file_reader_web.dart';
import 'services/platform_runtime_native.dart'
    if (dart.library.js_interop) 'services/platform_runtime_web.dart';
import 'services/run_tracker_service.dart';
import 'services/todoist_import_service.dart';
import 'ui/activity_history_view.dart';
import 'ui/ai_capture_page.dart';
import 'ui/ai_settings_view.dart';
import 'ui/app_section.dart';
import 'ui/app_undo.dart';
import 'ui/daily_step_goal_indicator.dart';
import 'ui/daily_steps_sheet.dart';
import 'ui/link_text_editing_controller.dart';
import 'ui/priority_color.dart';
import 'ui/quick_add_sheet.dart';
import 'ui/search.dart';
import 'ui/shell/app_update_flow.dart';
import 'ui/shell/civil_day_clock.dart';
import 'ui/sync_issues_view.dart';
import 'ui/task_link_dialog.dart';
import 'ui/todoist_link_text.dart';
import 'ui/views/agenda_day_view.dart';
import 'ui/views/agenda_event_flows.dart';
import 'ui/views/agenda_view.dart';
import 'ui/views/empty_view_label.dart';
import 'ui/views/projects_view.dart';
import 'ui/views/task_order.dart';
import 'ui/views/today_agenda_strip.dart';
import 'ui/views/today_view.dart';
import 'ui/views/upcoming_view.dart';

part 'ui/data_health_view.dart';
part 'ui/settings_view.dart';
part 'ui/sync_account_card.dart';
part 'ui/task_editor.dart';
part 'ui/task_widgets.dart';
part 'ui/trash_view.dart';
part 'ui/undated_tasks_view.dart';

const _pageMotion = Duration(milliseconds: 140);
const _pageMotionOut = Duration(milliseconds: 90);
const _microMotion = Duration(milliseconds: 110);

/// Android background job for the web Agenda (see agenda_background.dart).
@pragma('vm:entry-point')
Future<void> agendaBackgroundMain() => startAgendaBackground();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache
    ..maximumSize = 100
    ..maximumSizeBytes = 16 * 1024 * 1024;
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late final Future<_AppRuntime> initialization = _initialize();
  AppLifecycleListener? syncLifecycle;

  @override
  void dispose() {
    syncLifecycle?.dispose();
    super.dispose();
  }

  Future<_AppRuntime> _initialize() async {
    final startup = Stopwatch()..start();
    final diagnosticInitialization = DiagnosticLogService.instance
        .initialize()
        .catchError((Object _) {
          // La diagnostica non deve mai impedire l'avvio offline.
        });
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
    final supabaseInitialization = _initializeSupabase(
      url: supabaseUrl,
      key: supabaseKey,
    );
    await diagnosticInitialization;
    final syncClient = await supabaseInitialization;
    SyncService? syncService;
    if (syncClient != null) {
      syncService = SyncService(database, syncClient);
      // Bind first: an app started in background must not begin a cycle.
      syncLifecycle = bindSyncToLifecycle(syncService);
      syncService.start();
    }
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

  Future<SupabaseClient?> _initializeSupabase({
    required String url,
    required String key,
  }) async {
    if (url.isEmpty || key.isEmpty) return null;
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      postgrestOptions: const PostgrestClientOptions(
        requestTimeout: Duration(seconds: 20),
      ),
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSupabaseStorage(),
        autoRefreshToken: true,
      ),
    );
    return Supabase.instance.client;
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
  /// Brand colour: the + button, and red keeps meaning "attention"
  /// (overdue, high priority, delete, errors).
  static const brandRed = Color(0xffdb4035);

  /// Seed of the everyday accent (links, selection, today, buttons). Until
  /// build 217 the brand red was the primary colour too, so confirmations,
  /// links and plain buttons looked like errors (UI review, 5 October 2026).
  static const accentSeed = Color(0xff3b6fb6);

  const TodoApp({
    required this.repository,
    this.syncClient,
    this.syncService,
    this.enablePlatformServices = true,
    this.clock,
    super.key,
  });

  final TaskRepository repository;
  final SupabaseClient? syncClient;
  final SyncService? syncService;
  final bool enablePlatformServices;

  /// Wall clock for the civil day; only tests replace it.
  final DateTime Function()? clock;

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
    highContrastTheme: _theme(Brightness.light, highContrast: true),
    highContrastDarkTheme: _theme(Brightness.dark, highContrast: true),
    home: TaskShell(
      repository: repository,
      syncClient: syncClient,
      syncService: syncService,
      enablePlatformServices: enablePlatformServices,
      clock: clock,
    ),
  );

  ThemeData _theme(Brightness brightness, {bool highContrast = false}) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accentSeed,
          brightness: brightness,
        ).copyWith(
          outline: highContrast ? (dark ? Colors.white : Colors.black) : null,
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
      visualDensity: VisualDensity.standard,
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          height: 1.15,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        titleSmall: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        bodyMedium: const TextStyle(fontSize: 15, height: 1.3),
        bodySmall: const TextStyle(fontSize: 12, height: 1.25),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(48)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      checkboxTheme: const CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      focusColor: scheme.primary.withValues(alpha: highContrast ? 0.28 : 0.16),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandRed,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class TaskShell extends StatefulWidget {
  const TaskShell({
    required this.repository,
    this.syncClient,
    this.syncService,
    this.enablePlatformServices = true,
    this.clock,
    super.key,
  });

  final TaskRepository repository;
  final SupabaseClient? syncClient;
  final SyncService? syncService;
  final bool enablePlatformServices;
  final DateTime Function()? clock;

  @override
  State<TaskShell> createState() => _TaskShellState();
}

class _TaskShellState extends State<TaskShell> with WidgetsBindingObserver {
  AppSection section = AppSection.today;
  final List<AppSection> sectionHistory = [];
  String? selectedUpcomingDate;
  int upcomingDays = 30;
  int upcomingVisit = 0;
  var desktopEditorKey = GlobalKey<_TaskEditorState>();
  String? selectedProjectId;
  String? selectedDesktopTaskId;
  final search = TextEditingController();
  String? viewStreamKey;
  Stream<List<Task>>? viewStream;
  final updates = AppUpdateFlow();
  late final dayClock = CivilDayClock(now: widget.clock);

  /// Agenda on Android (phone calendars) and on the web (the phone's mirror,
  /// read-only, when sync is configured).
  bool get _agendaAvailable =>
      widget.enablePlatformServices &&
      (isAndroidPlatform || (isWebPlatform && widget.syncClient != null));

  late final AgendaService agendaService = isAndroidPlatform
      ? AgendaService(widget.repository.db)
      : WebAgendaService(widget.repository.db, widget.syncClient!);

  /// Phone side of the web Agenda (mirror upload, queued web edits); null
  /// elsewhere.
  late final AgendaPhoneSync? agendaSync =
      widget.enablePlatformServices &&
          isAndroidPlatform &&
          widget.syncClient != null
      ? AgendaPhoneSync(
          service: agendaService,
          client: widget.syncClient!,
          deviceId: widget.repository.deviceId,
        )
      : null;

  Stream<List<Task>> _visibleTasks() {
    final today = dayClock.today;
    final start = selectedUpcomingDate == null
        ? today.addDays(1)
        : CivilDate.parse(selectedUpcomingDate!);
    final key =
        '${section.name}:$today:$selectedProjectId:$start:$upcomingDays';
    if (key != viewStreamKey) {
      viewStreamKey = key;
      viewStream = widget.repository.watchView(
        view: section.name,
        today: today.toString(),
        projectId: selectedProjectId,
        fromDate: start.toString(),
        throughDate: start.addDays(upcomingDays - 1).toString(),
      );
    }
    return viewStream!;
  }

  bool backgroundSnapshotTaken = false;
  Timer? updateTimer;
  Timer? movementRefreshTimer;
  bool appIsForeground = true;
  final Set<String> recentlySyncedTaskIds = {};
  StreamSubscription<Set<String>>? remoteTaskSubscription;
  Timer? remoteHighlightTimer;
  List<Project> quickAddProjects = const [];
  String? lastQuickProjectId;
  DailyMovementProgress? dailyMovement;
  int dailyStepGoal = 10000;
  String? celebratedGoalDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // In background no frames are built, so this may run long after startup:
    // align the foreground bookkeeping with the current state.
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    if (isBackgroundLifecycle(initialLifecycle)) {
      didChangeAppLifecycleState(initialLifecycle!);
    }
    HardwareKeyboard.instance.addHandler(_handleDesktopEscape);
    dayClock.addListener(_onCivilDayChanged);
    unawaited(_initializeProjectCaches());
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.enablePlatformServices) return;
      await _refreshDailyMovement();
      unawaited(agendaSync?.attach());
      unawaited(agendaSync?.foreground());
      await _checkForUpdates(automatic: true);
      await _runDailyMaintenance();
      await _showDailyPerformanceReminder();
    });
    if (widget.enablePlatformServices && !isPlayDistribution) {
      updateTimer = Timer.periodic(const Duration(hours: 6), (_) {
        if (appIsForeground) unawaited(_checkForUpdates(automatic: true));
      });
    }
    if (widget.enablePlatformServices && isAndroidPlatform) {
      movementRefreshTimer = Timer.periodic(
        RunTrackerService.foregroundRefreshInterval,
        (_) {
          if (appIsForeground) unawaited(_refreshDailyMovement());
        },
      );
    }
  }

  Future<void> _refreshDailyMovement() async {
    if (!isAndroidPlatform) return;
    final results = await Future.wait<Object?>([
      RunTrackerService.dailyMovement(),
      RunTrackerService.getStepGoal(),
      (widget.repository.db.select(widget.repository.db.appSettings)
            ..where((row) => row.key.equals('step_goal_celebrated_day')))
          .getSingleOrNull(),
    ]);
    if (!mounted) return;
    final movement = results[0] as DailyMovementProgress?;
    final goal = results[1] as int;
    final savedCelebration = results[2] as AppSetting?;
    celebratedGoalDay ??= savedCelebration?.value;
    final reachedNow = movement != null && movement.steps >= goal;
    final shouldCelebrate = reachedNow && celebratedGoalDay != movement.day;
    setState(() {
      dailyMovement = movement;
      dailyStepGoal = goal;
      if (shouldCelebrate) celebratedGoalDay = movement.day;
    });
    if (shouldCelebrate) {
      await _savePreference('step_goal_celebrated_day', movement.day);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obiettivo passi raggiunto! Ottimo lavoro ★'),
          duration: Duration(seconds: 4),
          showCloseIcon: true,
        ),
      );
    }
  }

  Future<void> _showDailySteps() => showDailyStepsSheet(
    context,
    progress: dailyMovement,
    goal: dailyStepGoal,
    enableSteps: () async {
      await RunTrackerService.requestStepPermission();
      await _refreshDailyMovement();
    },
    editGoal: () async {
      final value = await showStepGoalDialog(context, dailyStepGoal);
      if (value != null) await _setDailyStepGoal(value);
    },
  );

  /// Task editor for a task shown in the Agenda.
  Future<void> _openTaskById(String id) async {
    final db = widget.repository.db;
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (task == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => TaskEditor(task: task, repository: widget.repository),
    );
  }

  Future<void> _setDailyStepGoal(int value) async {
    final goal = await RunTrackerService.setStepGoal(value);
    if (!mounted) return;
    setState(() {
      dailyStepGoal = goal;
      if ((dailyMovement?.steps ?? 0) < goal) celebratedGoalDay = null;
    });
  }

  Future<void> _initializeProjectCaches() async {
    final projects = await widget.repository.db
        .select(widget.repository.db.projects)
        .get();
    await _refreshQuickAddCache(projects: projects);
    if (mounted) setState(() {});
  }

  Future<void> _refreshQuickAddCache({List<Project>? projects}) async {
    projects ??= await widget.repository.db
        .select(widget.repository.db.projects)
        .get();
    final settings = await (widget.repository.db.select(
      widget.repository.db.appSettings,
    )..where((row) => row.key.equals('last_quick_project'))).get();
    final values = {for (final setting in settings) setting.key: setting.value};
    quickAddProjects = projects.where((item) => !item.isArchived).toList();
    lastQuickProjectId = values['last_quick_project'];
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enablePlatformServices) return;
    if (state == AppLifecycleState.resumed) {
      if (appIsForeground) return; // Only `inactive`: nothing was suspended.
      appIsForeground = true;
      backgroundSnapshotTaken = false;
      dayClock.refresh();
      unawaited(_refreshDailyMovement());
      unawaited(
        PerformanceMonitor.instance.snapshot('resumed', widget.repository.db),
      );
      if (updates.isDue(DateTime.now())) {
        unawaited(_checkForUpdates(automatic: true));
      }
      unawaited(agendaSync?.foreground());
    } else if (isBackgroundLifecycle(state)) {
      // Sync pause/resume is owned by [bindSyncToLifecycle].
      appIsForeground = false;
      if (!backgroundSnapshotTaken) {
        backgroundSnapshotTaken = true;
        unawaited(PerformanceMonitor.instance.flushFrames());
        final imageCache = PaintingBinding.instance.imageCache;
        imageCache
          ..clear()
          ..clearLiveImages();
        unawaited(
          PerformanceMonitor.instance.snapshot(
            'background',
            widget.repository.db,
          ),
        );
      }
    }
  }

  Future<void> _checkForUpdates({bool automatic = false}) =>
      updates.check(context, automatic: automatic);

  /// Date-derived views re-query when the civil day changes: see
  /// [CivilDayClock]. The change writes nothing.
  void _onCivilDayChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    agendaSync?.detach();
    HardwareKeyboard.instance.removeHandler(_handleDesktopEscape);
    updateTimer?.cancel();
    movementRefreshTimer?.cancel();
    remoteHighlightTimer?.cancel();
    remoteTaskSubscription?.cancel();
    dayClock
      ..removeListener(_onCivilDayChanged)
      ..dispose();
    search.dispose();
    super.dispose();
  }

  bool _handleDesktopEscape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        selectedDesktopTaskId == null) {
      return false;
    }
    unawaited(_closeDesktopEditor());
    return true;
  }

  Future<bool> _createFrom(
    QuickAddInput input, {
    required List<Project> projects,
  }) async {
    if (input.text.trim().isEmpty) return false;
    final elapsed = Stopwatch()..start();
    try {
      final metadata = parseQuickAddMetadata(
        input.text,
        defaultPriority: input.priority,
        defaultProjectId: input.projectId,
        projectsByName: {
          for (final project in projects.where((item) => !item.isArchived))
            project.name: project.id,
        },
      );
      final parsed = parsePlannedQuickTask(metadata.text);
      final notesText = input.notes.trim();
      await widget.repository.create(
        linkifyPlainUrls(parsed.title),
        showDate: parsed.showDate!.toString(),
        notes: notesText.isEmpty ? null : linkifyPlainUrls(notesText),
        recurrence: parsed.recurrence,
        priority: metadata.priority,
        projectId: metadata.projectId,
        sectionId: metadata.projectId == input.projectId
            ? input.sectionId
            : null,
      );
      await _savePreference('last_quick_project', metadata.projectId ?? '');
      lastQuickProjectId = metadata.projectId;
      if (mounted) setState(() => selectedDesktopTaskId = null);
      elapsed.stop();
      unawaited(
        DiagnosticLogService.instance.event(
          'interaction_latency',
          fields: {
            'interaction': 'task_submit',
            'outcome': 'success',
            'duration_ms': elapsed.elapsedMilliseconds,
          },
        ),
      );
      return true;
    } on FormatException catch (error) {
      elapsed.stop();
      unawaited(
        DiagnosticLogService.instance.event(
          'interaction_latency',
          level: 'warning',
          fields: {
            'interaction': 'task_submit',
            'outcome': 'invalid',
            'duration_ms': elapsed.elapsedMilliseconds,
          },
        ),
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString()), showCloseIcon: true),
      );
      return false;
    }
  }

  Future<void> _savePreference(String key, String value) => widget.repository.db
      .into(widget.repository.db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<void> _showQuickAddSheet({
    String? projectId,
    String? sectionId,
  }) async {
    if (!await _closeDesktopEditor() || !mounted) return;
    final projects = List<Project>.of(quickAddProjects);
    // Refresh in background for the next opening. The current sheet must be
    // mounted immediately, without waiting for SQLite or preferences.
    unawaited(_refreshQuickAddCache());
    await showQuickAddSheet(
      context,
      projects: projects,
      draftStore: EditorDrafts(widget.repository.db),
      projectId:
          projectId ??
          (projects.any((item) => item.id == lastQuickProjectId)
              ? lastQuickProjectId
              : null),
      sectionId: sectionId,
      onSubmit: (input) => _createFrom(input, projects: projects),
    );
  }

  bool get _canExitFromBack =>
      section == AppSection.today && sectionHistory.isEmpty;

  Future<void> _navigateTo(AppSection destination) async {
    if (destination == section) return;
    if (!await _closeDesktopEditor() || !mounted) return;
    final elapsed = Stopwatch()..start();
    setState(() {
      sectionHistory.add(section);
      if (sectionHistory.length > 20) sectionHistory.removeAt(0);
      section = destination;
      if (destination == AppSection.upcoming) {
        upcomingVisit++;
        upcomingDays = 30;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      elapsed.stop();
      unawaited(
        DiagnosticLogService.instance.event(
          'interaction_latency',
          fields: {
            'interaction': 'screen_change',
            'outcome': 'visible',
            'duration_ms': elapsed.elapsedMilliseconds,
          },
        ),
      );
    });
  }

  Future<void> _handleBack() async {
    if (selectedDesktopTaskId != null) {
      await _closeDesktopEditor();
      return;
    }
    setState(() {
      if (selectedDesktopTaskId != null) {
        selectedDesktopTaskId = null;
      } else if (section == AppSection.projects && selectedProjectId != null) {
        selectedProjectId = null;
      } else if (sectionHistory.isNotEmpty) {
        section = sectionHistory.removeLast();
        if (section == AppSection.upcoming) {
          upcomingVisit++;
          upcomingDays = 30;
        }
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
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
      },
      child: Actions(
        actions: {
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              _handleBack();
              return null;
            },
          ),
        },
        child: StreamBuilder<List<Task>>(
          stream: _visibleTasks(),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? const [];
            final primarySections = [
              AppSection.today,
              AppSection.upcoming,
              AppSection.projects,
              if (_agendaAvailable) AppSection.agenda,
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                final pageIdentity =
                    '${section.name}:'
                    '${section == AppSection.projects ? selectedProjectId ?? 'root' : ''}';
                final selectedDesktopTask = desktop
                    ? tasks
                          .where((task) => task.id == selectedDesktopTaskId)
                          .firstOrNull
                    : null;
                final content = Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: desktop ? 1180 : 720,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            key: const ValueKey('page-motion'),
                            duration: _pageMotion,
                            reverseDuration: _pageMotionOut,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.012, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: KeyedSubtree(
                              key: ValueKey('page-$pageIdentity'),
                              child: _content(tasks),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: _pageMotion,
                          reverseDuration: _pageMotionOut,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.centerRight,
                          child: selectedDesktopTask == null
                              ? const SizedBox.shrink()
                              : SizedBox(
                                  width: 331,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const VerticalDivider(width: 1),
                                      Expanded(
                                        child: ClipRect(
                                          child: _desktopItemDetails(
                                            selectedDesktopTask,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
                return Scaffold(
                  // Agenda gives its whole height to the days; search and
                  // settings move into its own header menu.
                  appBar: section == AppSection.agenda
                      ? null
                      : AppBar(
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
                          title: AnimatedSwitcher(
                            key: const ValueKey('appbar-title-motion'),
                            duration: _microMotion,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: Text(
                              section.label,
                              key: ValueKey('appbar-title-${section.name}'),
                            ),
                          ),
                          actions: [
                            // Steps only in Today: five actions cut the
                            // title elsewhere ("Prossi…", build 217).
                            if (widget.enablePlatformServices &&
                                isAndroidPlatform &&
                                section == AppSection.today)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: DailyStepGoalIndicator(
                                  key: const ValueKey('daily-step-goal'),
                                  steps: dailyMovement?.steps ?? 0,
                                  goal: dailyStepGoal,
                                  onTap: _showDailySteps,
                                ),
                              ),
                            if (widget.syncService != null)
                              SyncStatusAction(
                                service: widget.syncService!,
                                repository: widget.repository,
                              ),
                            if (section != AppSection.settings) ...[
                              if (widget.enablePlatformServices &&
                                  isAndroidPlatform)
                                IconButton(
                                  key: const ValueKey('ai-capture-open'),
                                  tooltip: 'Assistente: scrivi o detta',
                                  onPressed: _openAiCapture,
                                  icon: const Icon(Icons.auto_awesome),
                                ),
                              IconButton(
                                tooltip: 'Comando universale',
                                onPressed: _showUniversalCommand,
                                icon: const Icon(Icons.search_rounded),
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
                              selectedIndex: primarySections.contains(section)
                                  ? primarySections.indexOf(section)
                                  : null,
                              onDestinationSelected: (index) =>
                                  _navigateTo(primarySections[index]),
                              labelType: NavigationRailLabelType.all,
                              leading: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: IconButton.filled(
                                  tooltip: 'Nuova attività',
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
                          section != AppSection.agenda &&
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
                            // Same bar in every section (it was lower and
                            // without labels in Agenda until build 217).
                            child: NavigationBar(
                              height: 64,
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysShow,
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

  /// What the assistant may use: today, zone, projects, writable calendars
  /// shown in Agenda and their next 14 days of events (filters applied).
  Future<AiCaptureContext> _aiContext() async {
    final now = DateTime.now();
    final db = widget.repository.db;
    final projects =
        await (db.select(db.projects)
              ..where((p) => p.isArchived.equals(false))
              ..orderBy([(p) => OrderingTerm(expression: p.position)]))
            .get();
    final zone = await agendaService.deviceZoneLabel();
    var calendars = const <({String id, String name})>[];
    String? defaultCalendar;
    var upcoming =
        const <({String title, DateTime start, DateTime end, bool allDay})>[];
    if (await agendaService.access() == AgendaAccess.granted) {
      final all = await agendaService.calendars();
      final hidden = hiddenAgendaCalendars(
        all,
        await agendaService.calendarChoices(),
        hideHolidays: (await agendaService.filter()).hideHolidays,
      );
      calendars = [
        for (final calendar in all)
          if (calendar.writable && !hidden.contains(calendar.id))
            (id: calendar.id, name: calendar.name),
      ];
      // A separate ✨ calendar, if chosen and still writable, wins.
      final aiCalendar = await agendaService.aiEventCalendar();
      defaultCalendar = calendars.any((c) => c.id == aiCalendar)
          ? aiCalendar
          : defaultEventCalendar(
              all,
              await agendaService.lastEventCalendar(),
              hidden: hidden,
            );
      final today = DateTime(now.year, now.month, now.day);
      final events = await agendaService.events(
        today,
        today.add(const Duration(days: 14)),
        [
          for (final calendar in all)
            if (!hidden.contains(calendar.id)) calendar.id,
        ],
      );
      upcoming = [
        for (final entry in mergeAgendaEntries(
          events: events,
          calendars: all,
          hiddenCalendarIds: hidden,
          filter: await agendaService.filter(),
        ).take(80))
          (
            title: entry.title,
            start: entry.start,
            end: entry.end,
            allDay: entry.allDay,
          ),
      ];
    }
    return AiCaptureContext(
      now: now,
      zoneLabel: zone,
      projects: [for (final p in projects) (id: p.id, name: p.name)],
      calendars: calendars,
      defaultCalendarId: defaultCalendar,
      upcoming: upcoming,
    );
  }

  /// Writes confirmed proposals with the ✨ marker; dated tasks are also
  /// shown in the Agenda so the link between list and calendar is visible.
  /// Items written by the last ✨ creation, for its Annulla action.
  ({List<String> tasks, List<String> events}) _lastAiCreated = (
    tasks: const [],
    events: const [],
  );

  Future<int> _createAiProposals(List<AiProposal> items) async {
    final db = widget.repository.db;
    final links = AgendaTaskLinks(db);
    final taskIds = <String>[];
    final eventIds = <String>[];
    _lastAiCreated = (tasks: taskIds, events: eventIds);
    var created = 0;
    for (final item in items) {
      if (item.kind == AiProposalKind.task) {
        final id = await widget.repository.create(
          markAiTitle(item.title),
          showDate: item.date?.toString(),
          projectId: item.projectId,
          notes: item.storedNotes(),
        );
        taskIds.add(id);
        if (item.date != null) {
          final task = await (db.select(
            db.tasks,
          )..where((t) => t.id.equals(id))).getSingle();
          await links.setShown(task, true);
        }
      } else {
        final eventId = await agendaService.createEvent(
          AgendaEventDraft(
            calendarId: item.calendarId!,
            title: markAiTitle(item.title),
            start: item.start!,
            end: item.end!,
            allDay: item.allDay,
            location: item.location,
            notes: item.storedNotes(),
          ),
        );
        eventIds.add(eventId);
      }
      created++;
    }
    return created;
  }

  Future<void> _openAiCapture() async {
    final settings = AiSettings();
    final config = await settings.read();
    if (!mounted) return;
    if (!config.hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configura prima la chiave in Impostazioni → Assistente AI.',
          ),
        ),
      );
      return;
    }
    // Calendar colours for the proposal cards, even before Agenda opened.
    if (agendaService.lastCalendars == null &&
        await agendaService.access() == AgendaAccess.granted) {
      await agendaService.calendars();
    }
    if (!mounted) return;
    final created = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AiCapturePage(
          client: AiClient(settings),
          providerLabel: config.provider.label,
          loadContext: _aiContext,
          create: _createAiProposals,
          calendarColors: {
            for (final calendar
                in agendaService.lastCalendars ?? const <AgendaCalendar>[])
              calendar.id: parseCalendarColor(calendar.colorHex),
          },
        ),
      ),
    );
    if (created == null || created == 0 || !mounted) return;
    unawaited(agendaSync?.changed());
    final batch = _lastAiCreated;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          created == 1 ? 'Creato 1 elemento ✨' : 'Creati $created elementi ✨',
        ),
        action: SnackBarAction(
          label: 'Annulla',
          onPressed: () => unawaited(_undoAiCreation(batch)),
        ),
      ),
    );
  }

  /// Removes one ✨ batch: tasks go to the trash (recoverable), events are
  /// deleted from their calendar.
  Future<void> _undoAiCreation(
    ({List<String> tasks, List<String> events}) batch,
  ) async {
    final db = widget.repository.db;
    var failed = 0;
    for (final id in batch.tasks) {
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (task != null && task.deletedAt == null) {
        await widget.repository.softDelete(task);
      }
    }
    for (final id in batch.events) {
      try {
        await agendaService.deleteEvent(id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Creazione ✨ annullata. Le attività sono nel cestino.'
              : 'Annullato in parte: $failed eventi da togliere a mano.',
        ),
      ),
    );
  }

  /// Agenda flows built from what the service already knows, so search can
  /// open the same event detail as the Agenda.
  AgendaEventFlows _agendaFlows() {
    final calendars = agendaService.lastCalendars ?? const <AgendaCalendar>[];
    return AgendaEventFlows(
      service: agendaService,
      calendars: calendars,
      hidden: hiddenAgendaCalendars(
        calendars,
        agendaService.lastChoices ?? const {},
        hideHolidays:
            (agendaService.lastFilter ?? AgendaFilter.none).hideHolidays,
      ),
      zone: agendaService.lastZoneLabel,
      onOpenTask: _openTaskById,
      onCreateTask: _createLinkedTask,
    );
  }

  /// "Preparare" / "Follow-up" from an event: a dated task, also shown in
  /// the Agenda so it sits next to the meeting.
  Future<void> _createLinkedTask(
    String title,
    CivilDate date,
    String notes,
  ) async {
    final db = widget.repository.db;
    final id = await widget.repository.create(
      title,
      showDate: date.toString(),
      notes: notes,
    );
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await AgendaTaskLinks(db).setShown(task, true);
    unawaited(agendaSync?.changed());
  }

  Future<void> _showUniversalCommand() => showSearch<void>(
    context: context,
    delegate: TaskSearchDelegate(
      widget.repository,
      searchEvents: _agendaAvailable
          ? (text) async {
              try {
                final results = await agendaService.searchEvents(
                  text,
                  DateTime.now(),
                );
                // Zone for the detail sheet, as in the Agenda.
                await agendaService.deviceZoneLabel();
                return results;
              } catch (_) {
                return const [];
              }
            }
          : null,
      openEvent: (context, entry) => _agendaFlows().show(context, entry),
      tileBuilder: (task) => TaskTile(
        key: ValueKey('search-${task.id}'),
        task: task,
        repository: widget.repository,
      ),
      onNavigate: (destination) {
        _navigateTo(destination);
      },
      onCreate: (raw) async {
        final metadata = parseQuickAddMetadata(
          raw,
          defaultPriority: 1,
          projectsByName: const {},
        );
        final parsed = parsePlannedQuickTask(metadata.text);
        await widget.repository.create(
          parsed.title,
          showDate: parsed.showDate!.toString(),
          recurrence: parsed.recurrence,
          priority: metadata.priority,
        );
      },
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
        dailyStepGoal: dailyStepGoal,
        onDailyStepGoalChanged: _setDailyStepGoal,
      );
    }
    if (section == AppSection.agenda) {
      return SafeArea(
        bottom: false,
        child: AgendaView(
          service: agendaService,
          today: dayClock.today,
          onOpenTask: _openTaskById,
          onCreateTask: _createLinkedTask,
          onSearch: _showUniversalCommand,
          onCapture: isAndroidPlatform ? _openAiCapture : null,
          onSettings: () => _navigateTo(AppSection.settings),
          onChanged: () => unawaited(agendaSync?.changed()),
        ),
      );
    }
    if (section == AppSection.projects) {
      return ProjectsView(
        repository: widget.repository,
        syncService: widget.syncService,
        tasks: all,
        selectedProjectId: selectedProjectId,
        onSelectProject: (id) => setState(() => selectedProjectId = id),
        beforeLeavingProject: () async =>
            await _closeDesktopEditor() && mounted,
        onAddTask: (projectId, sectionId) =>
            _showQuickAddSheet(projectId: projectId, sectionId: sectionId),
        tileBuilder: (task) => TaskTile(
          key: ValueKey('project-${task.id}'),
          task: task,
          repository: widget.repository,
          highlightRemote: recentlySyncedTaskIds.contains(task.id),
        ),
      );
    }
    final today = dayClock.today;
    // Membership comes from SQL (`watchView`); here rows are only ordered.
    final visible = List<Task>.of(all)
      ..sort(
        (a, b) => section == AppSection.upcoming
            ? compareByDateThenPriority(a, b, today.toString())
            : compareByPriority(a, b, today.toString()),
      );
    if (section == AppSection.upcoming) {
      final start = selectedUpcomingDate == null
          ? today.addDays(1)
          : CivilDate.parse(selectedUpcomingDate!);
      return Column(
        children: [
          UpcomingDateJump(
            today: today,
            selected: selectedUpcomingDate == null ? null : start,
            onSelected: (date) => setState(() {
              selectedUpcomingDate = date.toString();
              upcomingDays = 30;
              upcomingVisit++;
            }),
          ),
          Expanded(
            child: UpcomingTaskList(
              listKey: PageStorageKey(
                'upcoming-$selectedUpcomingDate-$upcomingVisit',
              ),
              tasks: visible,
              today: today,
              start: start,
              days: upcomingDays,
              onLoadMore: () => setState(() => upcomingDays += 30),
              tileBuilder: (task) => TaskTile(
                key: ValueKey(task.id),
                task: task,
                repository: widget.repository,
                showDateMetadata: false,
                highlightRemote: recentlySyncedTaskIds.contains(task.id),
              ),
            ),
          ),
        ],
      );
    }
    final list = AnimatedSwitcher(
      key: ValueKey('task-state-motion-${section.name}'),
      duration: _microMotion,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: visible.isEmpty
          ? EmptyViewLabel(
              section == AppSection.completed
                  ? 'Nessuna attività completata'
                  : 'Nessuna attività',
              key: ValueKey('empty-${section.name}'),
            )
          : section == AppSection.today
          ? TodayTaskList(
              tasks: visible,
              today: today.toString(),
              tileBuilder: _taskTile,
            )
          : ListView.builder(
              key: PageStorageKey('task-list-${section.name}'),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: visible.length,
              itemBuilder: (context, index) => _taskTile(visible[index]),
            ),
    );
    if (section != AppSection.today || !_agendaAvailable) return list;
    // Today's remaining appointments above the tasks: one look for both.
    return Column(
      children: [
        TodayAgendaStrip(
          dayKey: today.toString(),
          loadEntries: () async =>
              (await agendaService.agendaDays(today, 1)).single.entries,
          onOpen: () => unawaited(_openAgendaDay(today)),
          colorOf: (entry) => parseCalendarColor(
            agendaService.lastCalendars
                ?.where((c) => c.id == entry.calendarIds.first)
                .firstOrNull
                ?.colorHex,
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  /// Day view of the Agenda opened from elsewhere (Today strip).
  Future<void> _openAgendaDay(CivilDate day) async {
    await agendaService.deviceZoneLabel();
    if (!mounted) return;
    final flows = _agendaFlows();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => AgendaDayPage(
          initialDay: day,
          today: dayClock.today,
          loadDays: agendaService.agendaDays,
          peekDays: (_, _) => null,
          colors: {
            for (final calendar in flows.calendars)
              calendar.id: parseCalendarColor(calendar.colorHex),
          },
          onOpen: (entry) => flows.show(pageContext, entry),
          onLongPress: (entry) => flows.quickActions(pageContext, entry),
          onCreate: (start, {end}) =>
              flows.create(pageContext, start: start, end: end),
          zoneLabel: agendaService.lastZoneLabel,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _taskTile(Task task) => TaskTile(
    key: ValueKey(task.id),
    task: task,
    repository: widget.repository,
    highlightRemote: recentlySyncedTaskIds.contains(task.id),
    dense: section == AppSection.completed,
    showDateMetadata:
        section != AppSection.today && section != AppSection.upcoming,
    onSelected: MediaQuery.sizeOf(context).width >= 900
        ? () async {
            if (selectedDesktopTaskId == task.id) return;
            if (await _closeDesktopEditor() && mounted) {
              setState(() {
                desktopEditorKey = GlobalKey<_TaskEditorState>();
                selectedDesktopTaskId = task.id;
              });
            }
          }
        : null,
  );

  Future<bool> _closeDesktopEditor() async {
    if (!await (desktopEditorKey.currentState?.preserveDraft() ??
        Future.value(true))) {
      return false;
    }
    if (mounted) setState(() => selectedDesktopTaskId = null);
    return true;
  }

  Widget _desktopItemDetails(Task task) => Padding(
    key: ValueKey('desktop-detail-${task.id}'),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dettagli',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Chiudi dettagli',
              onPressed: _closeDesktopEditor,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Focus(
            key: ValueKey('desktop-inline-editor-${task.id}'),
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                unawaited(_closeDesktopEditor());
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TaskEditor(
              key: desktopEditorKey,
              task: task,
              repository: widget.repository,
              embedded: true,
              onSaved: (_) => setState(() => selectedDesktopTaskId = null),
              onDeleted: () => setState(() => selectedDesktopTaskId = null),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pauses and resumes sync from the binding, next to [SyncService.start].
/// Widget observers are not enough: in background Flutter builds no frames,
/// so an app started there would never reach the widget that observes it.
AppLifecycleListener bindSyncToLifecycle(SyncService service) {
  if (isBackgroundLifecycle(WidgetsBinding.instance.lifecycleState)) {
    service.pause();
  }
  return AppLifecycleListener(
    onStateChange: (state) {
      if (isBackgroundLifecycle(state)) {
        service.pause();
      } else if (state == AppLifecycleState.resumed) {
        service.resume();
      }
    },
  );
}

/// Not visible to the user. `inactive` alone is a transient interruption.
bool isBackgroundLifecycle(AppLifecycleState? state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached ||
    state == AppLifecycleState.hidden;

class _BackIntent extends Intent {
  const _BackIntent();
}
