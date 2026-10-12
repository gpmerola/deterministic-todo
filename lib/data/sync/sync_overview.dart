import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'sync_request_scope.dart';
import 'task_fingerprints.dart';

class SyncOverview {
  SyncOverview(
    this.tasks,
    this.digests, {
    this.taskVersion = taskFingerprintV1,
  });
  final List<dynamic> tasks;
  final Map<String, String> digests;

  /// Fingerprint scheme of [tasks]: v2 (`todo_sync_overview_v2`) includes the
  /// row content, v1 only the version stamps.
  final int taskVersion;

  static Future<SyncOverview?> fetch(
    SupabaseClient client,
    SyncRequestScope scope,
  ) async {
    final fetched = await fetchWithFingerprintFallback(
      client,
      scope,
      rpcV2: 'todo_sync_overview_v2',
      rpcV1: 'todo_sync_overview_v1',
    );
    if (fetched == null) return null;
    final raw = Map<String, dynamic>.from(fetched.value as Map);
    if (raw['schema'] != fetched.version || raw['tasks'] is! List) {
      throw const FormatException('Invalid sync overview');
    }
    final digests = <String, String>{};
    for (final table in ['projects', 'project_sections', 'purged_entities']) {
      final digest = raw[table];
      if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        throw const FormatException('Invalid sync overview digest');
      }
      digests[table] = digest;
    }
    return SyncOverview(
      raw['tasks'] as List,
      digests,
      taskVersion: fetched.version,
    );
  }

  Future<bool> matches(AppDatabase db, String table, SyncRequestScope scope) =>
      scope.compareLocally(() async {
        if (!digests.containsKey(table)) {
          throw ArgumentError('Invalid overview table');
        }
        final rows = await db
            .customSelect(
              table == 'purged_entities'
                  ? '''
        SELECT group_concat(key || ';', '') AS signature
        FROM (SELECT key FROM app_settings WHERE key LIKE 'purged:%' ORDER BY key)
      '''
                  : '''
        SELECT group_concat(id || ':' || logical_version || ':' || device_id || ';', '') AS signature
        FROM (SELECT id, logical_version, device_id FROM "$table" ORDER BY id)
      ''',
            )
            .getSingle();
        scope.check();
        return sha256
                .convert(
                  utf8.encode(rows.readNullable<String>('signature') ?? ''),
                )
                .toString() ==
            digests[table];
      });
}
