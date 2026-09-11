import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'sync_request_scope.dart';

/// Null means the server predates the optional RPC: retain the complete scan.
/// Empty means all remote buckets match. Missing local rows, low-counter writes
/// from offline devices and tombstones all change a fingerprint, without clocks
/// or persistent watermarks. Never delete local rows based on a missing bucket.
Future<List<String>?> changedTaskBuckets(
  AppDatabase db,
  SupabaseClient client,
  SyncRequestScope scope,
) async {
  List<dynamic> remote;
  try {
    remote = await scope.send(client.rpc('todo_task_fingerprints_v1'));
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST202' || e.code == '42883') return null;
    rethrow;
  }
  final expected = <String, String>{};
  for (final item in remote) {
    final raw = Map<String, dynamic>.from(item as Map);
    final bucket = raw['bucket'] as String;
    final digest = raw['fingerprint'] as String;
    if (!RegExp(r'^[0-9a-f]{2}$').hasMatch(bucket) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        expected.containsKey(bucket)) {
      throw const FormatException('Invalid sync fingerprint response');
    }
    expected[bucket] = digest;
  }
  scope.check();
  if (expected.isEmpty) return [];
  // SQLite groups ordered metadata into at most 256 strings. Avoid 90k Dart
  // maps/isolate messages, selecting neither task text nor history.
  final local = await db.customSelect('''
    SELECT substr(id, 1, 2) AS bucket,
      group_concat(id || ':' || logical_version || ':' || device_id || ';', '') AS signature
    FROM (SELECT id, logical_version, device_id FROM tasks ORDER BY id)
    GROUP BY substr(id, 1, 2)
  ''').get();
  for (final row in local) {
    final bucket = row.read<String>('bucket');
    if (!expected.containsKey(bucket)) continue;
    if (sha256.convert(utf8.encode(row.read<String>('signature'))).toString() ==
        expected[bucket]) {
      expected.remove(bucket);
    }
  }
  scope.check();
  return expected.keys.toList()..sort();
}
