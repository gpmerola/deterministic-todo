import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import 'backup_gzip_io.dart'
    if (dart.library.js_interop) 'backup_gzip_web.dart';
import 'diagnostic_log_service.dart';
import 'export_service.dart';

/// One copy of the Todo backup JSON 2 kept in the user's Supabase account.
final class CloudBackupEntry {
  const CloudBackupEntry({
    required this.id,
    required this.savedAt,
    required this.sizeBytes,
    required this.deviceId,
  });
  final String id;
  final DateTime savedAt;

  /// Uncompressed JSON size.
  final int sizeBytes;
  final String deviceId;
}

/// What the server answers; injectable so tests need no network.
abstract interface class CloudBackupRemote {
  /// False without a signed-in account: nothing is attempted.
  bool get available;

  /// Content hash of the newest copy, or null when there is none.
  Future<String?> latestHash();

  /// 'saved' or 'unchanged'.
  Future<String> save({
    required String content,
    required String hash,
    required int size,
    required String deviceId,
  });

  /// Newest first, without content.
  Future<List<CloudBackupEntry>> list();
  Future<String> content(String id);
}

/// Table `todo_cloud_backups` and RPC `save_todo_cloud_backup_v1`
/// (migration 202611190001). RLS limits every read to the signed-in user.
final class SupabaseCloudBackupRemote implements CloudBackupRemote {
  const SupabaseCloudBackupRemote(this.client);
  final SupabaseClient client;
  static const _table = 'todo_cloud_backups';

  @override
  bool get available => client.auth.currentSession != null;

  @override
  Future<String?> latestHash() async {
    final row = await client
        .from(_table)
        .select('content_hash')
        .order('seq', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['content_hash'] as String?;
  }

  @override
  Future<String> save({
    required String content,
    required String hash,
    required int size,
    required String deviceId,
  }) async => await client.rpc<String>(
    'save_todo_cloud_backup_v1',
    params: {
      'backup_content': content,
      'backup_hash': hash,
      'backup_encoding': CloudBackupService.encoding,
      'backup_size': size,
      'backup_device': deviceId,
    },
  );

  @override
  Future<List<CloudBackupEntry>> list() async => [
    for (final row
        in await client
            .from(_table)
            .select('id, saved_at, size_bytes, device_id')
            .order('seq', ascending: false))
      CloudBackupEntry(
        id: row['id'] as String,
        savedAt: DateTime.parse(row['saved_at'] as String).toUtc(),
        sizeBytes: (row['size_bytes'] as num).toInt(),
        deviceId: row['device_id'] as String,
      ),
  ];

  @override
  Future<String> content(String id) async {
    final row = await client
        .from(_table)
        .select('content, encoding')
        .eq('id', id)
        .single();
    if (row['encoding'] != CloudBackupService.encoding) {
      throw const FormatException('unknown backup encoding');
    }
    return row['content'] as String;
  }
}

/// State shown in Impostazioni; [entries] is null when the server could not
/// be read (offline or migration missing).
final class CloudBackupStatus {
  const CloudBackupStatus({
    required this.entries,
    this.checkedAt,
    this.failedAt,
  });
  final List<CloudBackupEntry>? entries;
  final DateTime? checkedAt, failedAt;
  CloudBackupEntry? get latest =>
      entries == null || entries!.isEmpty ? null : entries!.first;
  bool get lastAttemptFailed =>
      failedAt != null &&
      (checkedAt == null || !failedAt!.isBefore(checkedAt!));
}

/// Top level for [compute]: gzip then base64, so the RPC carries text.
String encodeCloudBackup(Uint8List json) => base64Encode(gzipEncodeBytes(json));

/// Top level for [compute]: the JSON 2 text of a stored copy.
String decodeCloudBackup(String content) =>
    utf8.decode(gzipDecodeBytes(base64Decode(content)));

/// Daily off-phone copy of the Todo backup JSON 2. Runs only from the
/// existing start/resume hook: no timer, job or polling. A copy is uploaded
/// only when the content differs from the newest one in the account, so an
/// unchanged day costs one small read. The server keeps the newest
/// [keep] copies. Restoring goes through the ordinary import preview, which
/// asks for explicit confirmation; nothing here touches Todo data.
final class CloudBackupService {
  CloudBackupService(
    this.db,
    this.remote, {
    required this.deviceId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const interval = Duration(days: 1);
  static const retry = Duration(hours: 6);
  static const keep = 14;
  static const encoding = 'gzip-base64';
  static const lastAtKey = 'cloud_backup_last_at';
  static const attemptAtKey = 'cloud_backup_attempt_at';
  static const failedAtKey = 'cloud_backup_failed_at';

  final AppDatabase db;
  final CloudBackupRemote remote;
  final String deviceId;
  final DateTime Function() _now;
  Future<bool>? _running;

  /// True when a new copy was stored.
  Future<bool> runIfDue() => _running ??= _runIfDue().whenComplete(() {
    _running = null;
  });

  Future<bool> _runIfDue() async {
    if (!backupGzipSupported || !remote.available) return false;
    final now = _now().toUtc();
    final last = await _instant(lastAtKey);
    final attempt = await _instant(attemptAtKey);
    if (last != null && now.difference(last) < interval) return false;
    if (attempt != null &&
        (last == null || attempt.isAfter(last)) &&
        now.difference(attempt) < retry) {
      return false;
    }
    await _set(attemptAtKey, now.toIso8601String());
    try {
      return await backupNow(now: now);
    } on Object {
      return false; // Recorded and logged by [backupNow].
    }
  }

  /// "Crea ora" and the daily run. Throws after recording the failure.
  Future<bool> backupNow({DateTime? now}) async {
    final at = (now ?? _now()).toUtc();
    try {
      final written = await _backupNow(at);
      unawaited(
        DiagnosticLogService.instance.event(
          'cloud_backup_completed',
          fields: {'written': written},
        ),
      );
      return written;
    } on Object catch (error) {
      try {
        await _set(failedAtKey, at.toIso8601String());
      } on Object {
        // A failed database must not hide the original error.
      }
      // Only the type: the payload carries task titles and notes.
      unawaited(
        DiagnosticLogService.instance.event(
          'cloud_backup_failed',
          fields: {'error_type': error.runtimeType.toString()},
        ),
      );
      rethrow;
    }
  }

  Future<bool> _backupNow(DateTime now) async {
    final (:bytes, contentHash: hash) = await ExportService(db).exportBackup();
    var written = false;
    if (await remote.latestHash() != hash) {
      final content = bytes.length >= 64 * 1024
          ? await compute(encodeCloudBackup, bytes)
          : encodeCloudBackup(bytes);
      written =
          await remote.save(
            content: content,
            hash: hash,
            size: bytes.length,
            deviceId: deviceId,
          ) ==
          'saved';
    }
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.appSettings, [
        AppSettingsCompanion.insert(
          key: lastAtKey,
          value: now.toIso8601String(),
        ),
        AppSettingsCompanion.insert(key: failedAtKey, value: ''),
      ]),
    );
    return written;
  }

  Future<CloudBackupStatus> status() async {
    final checked = await _instant(lastAtKey);
    final failed = await _instant(failedAtKey);
    List<CloudBackupEntry>? entries;
    try {
      entries = await remote.list();
    } on Object {
      entries = null;
    }
    return CloudBackupStatus(
      entries: entries,
      checkedAt: checked,
      failedAt: failed,
    );
  }

  /// JSON 2 text, to be previewed and imported by [ExportService].
  Future<String> read(CloudBackupEntry entry) async {
    final content = await remote.content(entry.id);
    return content.length >= 64 * 1024
        ? compute(decodeCloudBackup, content)
        : decodeCloudBackup(content);
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
