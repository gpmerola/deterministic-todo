import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../data/local/database.dart';
import 'diagnostic_log_service.dart';
import 'export_service.dart';

/// One encrypted automatic backup on this phone.
final class AutoBackupEntry {
  const AutoBackupEntry(this.name, this.size);
  final String name;
  final int size;

  /// UTC instant encoded in the name `todo-YYYYMMDDTHHMMSSZ.tdb`.
  DateTime get savedAt {
    final s = name.substring(5, 21);
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(9, 11)),
      int.parse(s.substring(11, 13)),
      int.parse(s.substring(13, 15)),
    );
  }
}

/// Encryption, key and files live on the platform side (Android).
abstract interface class EncryptedBackupStore {
  /// True once [setup] created the data key on this installation.
  Future<bool> configured();

  /// Creates the data key if missing; returns its recovery code.
  Future<String> setup();
  Future<void> write(String name, Uint8List content, {required int keep});
  Future<List<AutoBackupEntry>> list();
  Future<Uint8List> read(String name);

  /// A picked `.tdb` file; [code] is needed for another installation's key.
  Future<Uint8List> decrypt(Uint8List content, {String? code});
}

/// Platform error codes: `key_mismatch`, `invalid_code`, `not_configured`.
final class MethodChannelBackupStore implements EncryptedBackupStore {
  const MethodChannelBackupStore();
  static const _channel = MethodChannel('app.deterministic.todo/backup');

  @override
  Future<bool> configured() async =>
      await _channel.invokeMethod<bool>('status') ?? false;

  @override
  Future<String> setup() async =>
      (await _channel.invokeMethod<String>('setup'))!;

  @override
  Future<void> write(String name, Uint8List content, {required int keep}) =>
      _channel.invokeMethod<int>('write', {
        'name': name,
        'content': content,
        'keep': keep,
      });

  @override
  Future<List<AutoBackupEntry>> list() async => [
    for (final raw in await _channel.invokeListMethod<Map>('list') ?? <Map>[])
      AutoBackupEntry(raw['name'] as String, (raw['size'] as num).toInt()),
  ];

  @override
  Future<Uint8List> read(String name) async =>
      (await _channel.invokeMethod<Uint8List>('read', {'name': name}))!;

  @override
  Future<Uint8List> decrypt(Uint8List content, {String? code}) async =>
      (await _channel.invokeMethod<Uint8List>('decrypt', {
        'content': content,
        'code': ?code,
      }))!;
}

/// Weekly encrypted snapshot of the Todo backup JSON 2. After the one-time
/// activation (which reveals the recovery code) it needs no user action.
/// Runs only from existing app start/resume hooks: no timer, job or polling.
/// An unchanged export is not written again, so the kept history spans more
/// weeks; a failure is retried at most once a day and never blocks the UI.
final class AutoBackupService {
  AutoBackupService(
    this.db, {
    this.store = const MethodChannelBackupStore(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const interval = Duration(days: 7);
  static const retry = Duration(days: 1);
  static const keep = 6;
  static const lastAtKey = 'auto_backup_last_at';
  static const attemptAtKey = 'auto_backup_attempt_at';
  static const hashKey = 'auto_backup_hash';

  final AppDatabase db;
  final EncryptedBackupStore store;
  final DateTime Function() _now;
  Future<bool>? _running;

  /// True when a new file was written.
  Future<bool> runIfDue() => _running ??= _runIfDue().whenComplete(() {
    _running = null;
  });

  Future<bool> _runIfDue() async {
    final now = _now().toUtc();
    final last = await _instant(lastAtKey);
    final attempt = await _instant(attemptAtKey);
    if (last != null && now.difference(last) < interval) return false;
    if (attempt != null &&
        (last == null || attempt.isAfter(last)) &&
        now.difference(attempt) < retry) {
      return false;
    }
    try {
      if (!await store.configured()) return false;
      await _set(attemptAtKey, now.toIso8601String());
      return await backupNow(now: now);
    } on Object catch (error) {
      unawaited(
        DiagnosticLogService.instance.event(
          'auto_backup_failed',
          fields: {'error_type': error.runtimeType.toString()},
        ),
      );
      return false;
    }
  }

  /// Also used by tests; [now] names the file.
  Future<bool> backupNow({DateTime? now}) async {
    now = (now ?? _now()).toUtc();
    final json = await ExportService(db).exportJson();
    final bytes = Uint8List.fromList(utf8.encode(json));
    // `exported_at` changes every time; the content hash must not.
    final hash = sha256
        .convert(
          utf8.encode(json.replaceFirst(RegExp(r'"exported_at": "[^"]*"'), '')),
        )
        .toString();
    final previous = await _value(hashKey);
    final files = await store.list();
    final changed = previous != hash || files.isEmpty;
    if (changed) {
      await store.write(fileName(now), bytes, keep: keep);
    }
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.appSettings, [
        AppSettingsCompanion.insert(
          key: lastAtKey,
          value: now!.toIso8601String(),
        ),
        AppSettingsCompanion.insert(key: hashKey, value: hash),
      ]),
    );
    unawaited(
      DiagnosticLogService.instance.event(
        'auto_backup_completed',
        fields: {'written': changed, 'bytes': bytes.length},
      ),
    );
    return changed;
  }

  /// Decrypted JSON 2 text, to be previewed and imported by [ExportService].
  Future<String> read(AutoBackupEntry entry) async =>
      utf8.decode(await store.read(entry.name));

  /// A `.tdb` file chosen by the user, possibly from another installation.
  Future<String> decryptFile(Uint8List content, {String? code}) async =>
      utf8.decode(await store.decrypt(content, code: code));

  Future<bool> configured() => store.configured();

  /// Idempotent once activated: the existing key's code.
  Future<String> recoveryCode() => store.setup();

  /// One-time activation: returns the recovery code and writes a first backup.
  Future<String> activate() async {
    final code = await store.setup();
    try {
      await backupNow();
    } on Object catch (error) {
      unawaited(
        DiagnosticLogService.instance.event(
          'auto_backup_failed',
          fields: {'error_type': error.runtimeType.toString()},
        ),
      );
    }
    return code;
  }

  Future<List<AutoBackupEntry>> list() async =>
      (await store.list())..sort((a, b) => b.name.compareTo(a.name));

  static String fileName(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'todo-${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}'
        'Z.tdb';
  }

  Future<String?> _value(String key) async => (await (db.select(
    db.appSettings,
  )..where((r) => r.key.equals(key))).getSingleOrNull())?.value;

  Future<DateTime?> _instant(String key) async =>
      DateTime.tryParse(await _value(key) ?? '');

  Future<void> _set(String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
}
