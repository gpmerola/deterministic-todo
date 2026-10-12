import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../data/sync/secure_supabase_storage.dart';
import '../data/sync/sync_service.dart';
import '../data/task_repository.dart';
import 'diagnostic_log_service.dart';
import 'performance_monitor.dart';

/// Local startup and optional remote startup have independent failure domains.
/// The caller starts remote services only after the local UI has painted.
class AppRuntime extends ChangeNotifier {
  AppRuntime({
    Future<TaskRepository> Function()? openLocal,
    Future<SupabaseClient?> Function()? openRemote,
    this.beforeSyncStart,
  }) : _openLocal = openLocal ?? openLocalRepository,
       _openRemote = openRemote ?? openSupabase;
  final Future<TaskRepository> Function() _openLocal;
  final Future<SupabaseClient?> Function() _openRemote;
  final void Function(SyncService)? beforeSyncStart;
  TaskRepository? repository;
  SupabaseClient? syncClient;
  SyncService? syncService;
  Object? localError;
  bool remoteFailed = false;
  bool _disposed = false;
  Future<void>? _localOpening;
  Future<void>? _remoteOpening;
  bool _remoteOpened = false;

  Future<void> open() => _localOpening ??= _open();
  Future<void> _open() async {
    final timer = Stopwatch()..start();
    // Telemetry must never hold local startup hostage.
    final diagnostics = DiagnosticLogService.instance.initialize().catchError(
      (Object _) {},
    );
    try {
      final local = await _openLocal();
      if (_disposed) return;
      repository = local;
      PerformanceMonitor.instance.start();
      final duration = timer.elapsedMilliseconds;
      unawaited(
        diagnostics.then(
          (_) => PerformanceMonitor.instance.snapshot(
            'startup',
            local.db,
            durationMs: duration,
          ),
        ),
      );
    } catch (error) {
      localError = error;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> openRemote() {
    if (_disposed || repository == null || _remoteOpened) return Future.value();
    return _remoteOpening ??= _openServices().whenComplete(
      () => _remoteOpening = null,
    );
  }

  Future<void> _openServices() async {
    remoteFailed = false;
    if (!_disposed) notifyListeners();
    SyncService? starting;
    try {
      final client = await _openRemote();
      if (_disposed) return;
      if (client != null) {
        final service = starting = SyncService(repository!.db, client);
        beforeSyncStart?.call(service);
        service.start();
        syncClient = client;
        syncService = service;
      }
      _remoteOpened = true;
    } catch (_) {
      await starting?.dispose();
      remoteFailed = true;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(syncService?.dispose());
    super.dispose();
  }
}

Future<TaskRepository> openLocalRepository() async {
  final db = AppDatabase();
  final stored = await (db.select(
    db.appSettings,
  )..where((setting) => setting.key.equals('device_id'))).getSingleOrNull();
  var deviceId = stored?.value;
  if (deviceId == null) {
    try {
      const storage = FlutterSecureStorage();
      deviceId = await storage.read(key: 'device_id') ?? const Uuid().v4();
      await storage.write(key: 'device_id', value: deviceId);
    } on Object {
      deviceId = const Uuid().v4();
    }
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: 'device_id', value: deviceId),
        );
  }
  return TaskRepository(db, deviceId: deviceId);
}

Future<SupabaseClient?> openSupabase() async {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
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
