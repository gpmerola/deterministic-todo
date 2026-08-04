import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Log diagnostico locale privo di contenuto utente. Conserva al massimo due
/// file da 512 KiB e non registra mai titoli, note, email, token o URL.
class DiagnosticLogService {
  DiagnosticLogService._();

  static final instance = DiagnosticLogService._();
  static const _maxBytes = 512 * 1024;
  File? _file;
  Future<void> _pending = Future.value();

  Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    _file = File('${directory.path}/diagnostics.jsonl');
    await event('app_started', fields: {'platform': Platform.operatingSystem});
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
    _pending = _pending.then((_) async {
      final file = _file;
      if (file == null) return;
      await _rotateIfNeeded(file);
      await file.writeAsString(
        '${jsonEncode({'timestamp': DateTime.now().toUtc().toIso8601String(), 'level': level, 'event': name, ...allowed})}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    return _pending;
  }

  Future<File?> exportFile() async {
    await _pending;
    final file = _file;
    if (file == null || !await file.exists()) return null;
    return file;
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists() || await file.length() < _maxBytes) return;
    final previous = File('${file.path}.1');
    if (await previous.exists()) await previous.delete();
    await file.rename(previous.path);
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
    'error_type',
    'error_code',
    'duration_ms',
  };
}
