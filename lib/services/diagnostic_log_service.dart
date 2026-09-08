import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'diagnostic_store.dart';
import 'diagnostic_store_native.dart'
    if (dart.library.js_interop) 'diagnostic_store_web.dart';
import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

class DiagnosticExport {
  const DiagnosticExport(this.bytes, this.name);

  final Uint8List bytes;
  final String name;
}

/// Log diagnostico privo di contenuto utente. Conserva al massimo 512 KiB e
/// non registra mai titoli, note, email, token o URL.
class DiagnosticLogService {
  DiagnosticLogService._();

  static final instance = DiagnosticLogService._();
  static const _maxBytes = 512 * 1024;
  late final DiagnosticStore _store;
  Future<void> _pending = Future.value();
  bool _initialized = false;
  String _version = 'unknown';
  String _build = 'unknown';
  final String _session = const Uuid().v4();

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _store = await createDiagnosticStore(maxBytes: _maxBytes);
    try {
      final package = await PackageInfo.fromPlatform();
      _version = package.version;
      _build = package.buildNumber;
    } on Object {
      // I metadati di build arricchiscono il log ma non sono obbligatori.
    }
    _initialized = true;
    await event('app_started', fields: {'platform': operatingSystemName});
  }

  Future<void> event(
    String name, {
    String level = 'info',
    Map<String, Object?> fields = const {},
  }) {
    final allowed = <String, Object?>{
      for (final entry in fields.entries)
        if (_allowedKeys.contains(entry.key)) entry.key: entry.value,
    };
    _pending = _pending.catchError((Object _) {}).then((_) async {
      if (!_initialized) return;
      try {
        await _store.append(
          '${jsonEncode({'timestamp': DateTime.now().toUtc().toIso8601String(), 'level': level, 'event': name, 'version': _version, 'build': _build, 'log_schema': 1, 'session': _session, ...allowed})}\n',
        );
      } on Object {
        // La diagnostica non deve mai impedire l'uso dell'app.
      }
    });
    return _pending;
  }

  Future<DiagnosticExport?> exportData() async {
    await _pending;
    if (!_initialized) return null;
    final bytes = await _store.read();
    if (bytes.isEmpty) return null;
    return DiagnosticExport(bytes, 'diagnostics.jsonl');
  }

  static const _allowedKeys = {
    'platform',
    'phase',
    'pending',
    'count',
    'projects',
    'sections',
    'tasks',
    'updated',
    'removed',
    'version',
    'build',
    'log_schema',
    'session',
    'error_type',
    'error_code',
    'duration_ms',
    'rss_bytes',
    'total_pss_bytes',
    'java_heap_bytes',
    'native_heap_bytes',
    'graphics_bytes',
    'db_bytes',
    'active_tasks',
    'completed_tasks',
    'outbox',
    'frames',
    'slow_frames',
    'slow_frames_8ms',
    'build_us_avg',
    'build_us_max',
    'raster_us_avg',
    'raster_us_max',
    'remote_rows',
    'uploaded_entities',
    'rebased_entities',
    'cycle_id',
    'sync_stage',
    'error_class',
    'network_state',
    'auth_state',
    'failure_index',
    'retry_delay_ms',
    'retry_at',
    'outbox_oldest_age_ms',
    'recovered_failures',
    'local_won',
    'skipped_projects',
    'skipped_sections',
    'channel',
    'status',
    'result',
    'automatic',
    'interaction',
    'outcome',
  };
}
