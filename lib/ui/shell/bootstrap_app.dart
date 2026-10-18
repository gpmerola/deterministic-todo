part of '../../main.dart';

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    this.runtime,
    this.enablePlatformServices = true,
    super.key,
  });
  final AppRuntime? runtime;
  final bool enablePlatformServices;
  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late final AppRuntime runtime =
      widget.runtime ??
      AppRuntime(
        beforeSyncStart: (service) {
          syncLifecycle?.dispose();
          syncLifecycle = bindSyncToLifecycle(service);
          guardPageUnload(() => service.hasUnsentWork);
        },
      );
  AppLifecycleListener? syncLifecycle;
  bool remoteScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(runtime.open());
  }

  @override
  void dispose() {
    syncLifecycle?.dispose();
    runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) {
      final repository = runtime.repository;
      if (repository != null) {
        if (!remoteScheduled) {
          remoteScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(runtime.openRemote());
          });
        }
        return TodoApp(
          repository: repository,
          syncClient: runtime.syncClient,
          syncService: runtime.syncService,
          startupError: runtime.remoteFailed,
          onRetryStartup: runtime.openRemote,
          enablePlatformServices: widget.enablePlatformServices,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: runtime.localError == null
                ? const CircularProgressIndicator()
                : const Text(
                    'Impossibile aprire i dati locali. Riavvia l’app.',
                  ),
          ),
        ),
      );
    },
  );
}
