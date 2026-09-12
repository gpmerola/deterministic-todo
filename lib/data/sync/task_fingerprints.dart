import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
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
  SyncRequestScope scope, {
  List<dynamic>? fingerprints,
}) async {
  List<dynamic> remote;
  try {
    remote =
        fingerprints ??
        await scope.send(client.rpc('todo_task_fingerprints_v1'));
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
  final local = await scope.compareLocally(
    () => cachedTaskFingerprints(db, expected.keys.toList(), scope),
  );
  for (final e in local.entries) {
    if (expected[e.key] == e.value) expected.remove(e.key);
  }
  scope.check();
  return expected.keys.toList()..sort();
}

/// Cache reads, recomputation and replacement share one transaction. A write
/// either precedes this snapshot or invalidates its cache on the same commit.
Future<Map<String, String>> cachedTaskFingerprints(
  AppDatabase db,
  List<String> buckets,
  SyncRequestScope scope,
) => db.transaction(() async {
  scope.check();
  const prefix = 'sync_fp:v1:tasks:';
  final cached = await db
      .customSelect(
        'SELECT key, value FROM app_settings WHERE key IN (SELECT value FROM json_each(?))',
        variables: [
          Variable(jsonEncode(buckets.map((b) => '$prefix$b').toList())),
        ],
      )
      .get();
  final result = {
    for (final r in cached)
      r.read<String>('key').substring(prefix.length): r.read<String>('value'),
  };
  final missing = buckets.where((b) => !result.containsKey(b)).toList();
  if (missing.isNotEmpty) {
    final rows = await db
        .customSelect(
          '''
      SELECT substr(id, 1, 2) AS bucket,
        group_concat(id || ':' || logical_version || ':' || device_id || ';', '') AS signature
      FROM (SELECT id, logical_version, device_id FROM tasks
        WHERE substr(id, 1, 2) IN (SELECT value FROM json_each(?)) ORDER BY id)
      GROUP BY substr(id, 1, 2)
    ''',
          variables: [Variable(jsonEncode(missing))],
        )
        .get();
    final signatures = {
      for (final r in rows)
        r.read<String>('bucket'): r.read<String>('signature'),
    };
    for (final bucket in missing) {
      result[bucket] = sha256
          .convert(utf8.encode(signatures[bucket] ?? ''))
          .toString();
    }
    await db.batch(
      (b) => b.insertAllOnConflictUpdate(db.appSettings, [
        for (final bucket in missing)
          AppSettingsCompanion.insert(
            key: '$prefix$bucket',
            value: result[bucket]!,
          ),
      ]),
    );
  }
  scope.check();
  return result;
});
