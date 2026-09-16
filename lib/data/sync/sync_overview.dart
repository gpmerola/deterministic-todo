import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'sync_request_scope.dart';

class SyncOverview {
  SyncOverview(this.tasks, this.digests);
  final List<dynamic> tasks;
  final Map<String, String> digests;

  static Future<SyncOverview?> fetch(
    SupabaseClient client,
    SyncRequestScope scope,
  ) async {
    dynamic response;
    try {
      response = await scope.send(client.rpc('todo_sync_overview_v1'));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
    final raw = Map<String, dynamic>.from(response as Map);
    if (raw['schema'] != 1 || raw['tasks'] is! List) {
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
    return SyncOverview(raw['tasks'] as List, digests);
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
