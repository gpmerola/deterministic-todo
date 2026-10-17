part of '../../main.dart';

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
    this.startupError = false,
    this.onRetryStartup,
    super.key,
  });

  final bool startupError;
  final VoidCallback? onRetryStartup;
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
    builder: (context, child) => Stack(
      children: [
        child!,
        if (startupError)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Attività disponibili sul dispositivo. Sincronizzazione non avviata.',
                        ),
                      ),
                      TextButton(
                        onPressed: onRetryStartup,
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
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
