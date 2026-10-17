import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'sync_request_scope.dart';

/// v1 signs `id:version:device;` per row. v2 appends the user-visible content,
/// so a row that diverged at an equal version (the build 246 «hinge» case)
/// changes its bucket and is rewritten by the next bucket pull.
const taskFingerprintV1 = 1;
const taskFingerprintV2 = 2;

/// Content columns of v2, in signature order. Text is length-prefixed in code
/// points (`5#hello`), integers are decimal, null is `-`, fields join with `,`.
/// `time_minutes`/`time_zone` are excluded: the client stores them as null.
/// Must stay identical to `todo_task_fingerprints_v2` in Supabase.
const taskFingerprintTextFields = [
  'title',
  'notes',
  'item_kind',
  'status',
  'show_date',
  'project_id',
  'section_id',
  'recurrence',
  'series_id',
  'occurrence_key',
];
const taskFingerprintFields = [
  'title',
  'notes',
  'item_kind',
  'status',
  'show_date',
  'priority',
  'project_id',
  'section_id',
  'position',
  'recurrence',
  'series_id',
  'occurrence_key',
  'completed_at',
  'deleted_at',
];

/// Reference implementation for one server-shaped row (snake_case keys).
/// SQLite and Postgres compute the same string in SQL; tests compare all three.
String taskRowSignature(Map<String, dynamic> row, int version) {
  final stamp = '${row['id']}:${row['logical_version']}:${row['device_id']}';
  if (version == taskFingerprintV1) return '$stamp;';
  final content = [
    for (final field in taskFingerprintFields)
      switch (row[field]) {
        null => '-',
        final String text when taskFingerprintTextFields.contains(field) =>
          '${text.runes.length}#$text',
        final value => '$value',
      },
  ].join(',');
  return '$stamp:$content;';
}

String _sqliteRowSignature(int version) {
  const stamp = "id || ':' || logical_version || ':' || device_id";
  if (version == taskFingerprintV1) return "$stamp || ';'";
  final columns = [
    for (final field in taskFingerprintFields)
      taskFingerprintTextFields.contains(field)
          ? "coalesce(length($field) || '#' || $field, '-')"
          : "coalesce($field, '-')",
  ].join(" || ',' || ");
  return "$stamp || ':' || $columns || ';'";
}

/// Remembers per client that the server has no v2 RPCs, so the fallback costs
/// one failed request per process rather than one per cycle.
final _v2Missing = Expando<bool>('task fingerprints v2 missing');

bool _isMissingRpc(PostgrestException e) =>
    e.code == 'PGRST202' || e.code == '42883';

/// Fetches the newest supported fingerprint list, or null when neither RPC
/// exists. [rpcV2]/[rpcV1] let the overview reuse the same fallback.
Future<({dynamic value, int version})?> fetchWithFingerprintFallback(
  SupabaseClient client,
  SyncRequestScope scope, {
  required String rpcV2,
  required String rpcV1,
}) async {
  if (_v2Missing[client] != true) {
    try {
      return (
        value: await scope.send(client.rpc(rpcV2)),
        version: taskFingerprintV2,
      );
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e)) rethrow;
      _v2Missing[client] = true;
    }
  }
  try {
    return (
      value: await scope.send(client.rpc(rpcV1)),
      version: taskFingerprintV1,
    );
  } on PostgrestException catch (e) {
    if (_isMissingRpc(e)) return null;
    rethrow;
  }
}

/// Null means the server predates the optional RPC: retain the complete scan.
/// Empty buckets means all remote buckets match. Missing local rows, low-counter
/// writes from offline devices, tombstones and (v2) equal-version content
/// differences all change a fingerprint, without clocks or persistent
/// watermarks. Never delete local rows based on a missing bucket.
Future<({List<String> buckets, List<dynamic> remote, int version})?>
changedTaskBuckets(
  AppDatabase db,
  SupabaseClient client,
  SyncRequestScope scope, {
  List<dynamic>? fingerprints,
  int version = taskFingerprintV1,
}) async {
  var remote = fingerprints;
  if (remote == null) {
    final fetched = await fetchWithFingerprintFallback(
      client,
      scope,
      rpcV2: 'todo_task_fingerprints_v2',
      rpcV1: 'todo_task_fingerprints_v1',
    );
    if (fetched == null) return null;
    remote = fetched.value as List;
    version = fetched.version;
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
  if (expected.isEmpty) {
    return (buckets: <String>[], remote: remote, version: version);
  }
  final local = await scope.compareLocally(
    () => cachedTaskFingerprints(
      db,
      expected.keys.toList(),
      scope,
      version: version,
    ),
  );
  for (final e in local.entries) {
    if (expected[e.key] == e.value) expected.remove(e.key);
  }
  scope.check();
  return (
    buckets: expected.keys.toList()..sort(),
    remote: remote,
    version: version,
  );
}

/// Diagnostic only: [buckets] that still differ from [remote] after their
/// pull, excluding buckets with pending local task intents. A write made after
/// the server snapshot is also counted; a repeated non-zero value across cycles
/// indicates a divergence the pull cannot repair (for example a local-only row).
Future<int> unresolvedTaskBuckets(
  AppDatabase db,
  List<dynamic> remote,
  List<String> buckets,
  SyncRequestScope scope, {
  int version = taskFingerprintV1,
}) async {
  if (buckets.isEmpty) return 0;
  final expected = {
    for (final item in remote)
      (item as Map)['bucket'] as String: item['fingerprint'] as String,
  };
  final local = await scope.compareLocally(
    () => cachedTaskFingerprints(db, buckets, scope, version: version),
  );
  final pending =
      (await db
              .customSelect(
                'SELECT DISTINCT substr(entity_id, 1, 2) AS bucket FROM outbox_entries '
                "WHERE operation NOT IN ('projects', 'project_sections')",
              )
              .get())
          .map((row) => row.read<String>('bucket'))
          .toSet();
  scope.check();
  return buckets
      .where((b) => !pending.contains(b) && local[b] != expected[b])
      .length;
}

/// Cache reads, recomputation and replacement share one transaction. A write
/// either precedes this snapshot or invalidates its cache on the same commit.
/// The trigger-maintained slot `sync_fp:v1:tasks:<bucket>` holds one digest;
/// a v2 digest is stored as `v2:<hex>`, so a value of the other version is a
/// cache miss and no schema migration is needed for the new triggers.
Future<Map<String, String>> cachedTaskFingerprints(
  AppDatabase db,
  List<String> buckets,
  SyncRequestScope scope, {
  int version = taskFingerprintV1,
}) => db.transaction(() async {
  scope.check();
  const prefix = 'sync_fp:v1:tasks:';
  final tag = version == taskFingerprintV1 ? '' : 'v$version:';
  final cached = await db
      .customSelect(
        'SELECT key, value FROM app_settings WHERE key IN (SELECT value FROM json_each(?))',
        variables: [
          Variable(jsonEncode(buckets.map((b) => '$prefix$b').toList())),
        ],
      )
      .get();
  final result = <String, String>{};
  for (final r in cached) {
    final value = r.read<String>('value');
    final isTagged = value.length == 64 + tag.length && value.startsWith(tag);
    if (isTagged) {
      result[r.read<String>('key').substring(prefix.length)] = value.substring(
        tag.length,
      );
    }
  }
  final missing = buckets.where((b) => !result.containsKey(b)).toList();
  if (missing.isNotEmpty) {
    final rows = await db
        .customSelect(
          '''
      SELECT substr(id, 1, 2) AS bucket,
        group_concat(${_sqliteRowSignature(version)}, '') AS signature
      FROM (SELECT * FROM tasks
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
            value: '$tag${result[bucket]!}',
          ),
      ]),
    );
  }
  scope.check();
  return result;
});
