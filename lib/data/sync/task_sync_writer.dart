import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';

/// An old outbox has no field-level intent. Never guess and overwrite a server row.
final class SyncIntentConflictException implements Exception {
  const SyncIntentConflictException();
}

final class SyncConcurrentWriteException implements Exception {
  const SyncConcurrentWriteException();
}

Map<String, dynamic> taskToRemote(Task task, String userId) => {
  for (final entry in task.toJson().entries)
    entry.key.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m[0]!.toLowerCase()}',
    ): entry.value,
  'user_id': userId,
};

Task taskFromRemote(Map<String, dynamic> row) => Task.fromJson({
  for (final entry in row.entries)
    entry.key.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase()):
        entry.value,
  'itemKind': row['item_kind'] ?? 'task',
  'priority': row['priority'] ?? 1,
  'dueDate': null,
  'timeMinutes': null,
  'timeZone': null,
});

const _stamps = {'user_id', 'updated_at', 'logical_version', 'device_id'};
bool _sameContent(Map<String, dynamic> a, Map<String, dynamic> b) => a.keys
    .where((key) => !_stamps.contains(key))
    .every((key) => a[key] == b[key]);

Map<String, dynamic> syncReceipt(OutboxEntry entry) {
  final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
  return {
    'schema': 2,
    'id': entry.entityId,
    'version': payload['version'] ?? payload['logical_version'],
    'kind': payload['kind'] ?? 'legacy',
    'entity_type': payload['table'] ?? 'tasks',
    'changed_fields': (payload['changes'] as Map?)?.keys.toList() ?? [],
  };
}

/// Reads the latest row, applies only captured intent and conditionally writes it.
/// The version predicate is evaluated by Postgres in the same UPDATE statement.
class TaskSyncWriter {
  TaskSyncWriter(this.db, this.client);
  final AppDatabase db;
  final SupabaseClient client;

  Future<({Map<String, dynamic> row, int retries})> upload(
    Task initial,
    List<OutboxEntry> entries,
  ) async {
    final userId = client.auth.currentUser!.id;
    final pending = entries
        .where((e) => (jsonDecode(e.payload) as Map)['confirmed'] != true)
        .toList();
    final operations = pending
        .map((e) => jsonDecode(e.payload) as Map<String, dynamic>)
        .toList();
    final operationIds = entries.map((e) => e.operationId).toList();
    final replacement = operations.any((op) => op['kind'] == 'replace');
    final legacy = !replacement && operations.any((op) => op['schema'] != 2);
    for (var attempt = 0; attempt < 4; attempt++) {
      final rows = await client
          .from('tasks')
          .select()
          .eq('id', initial.id)
          .limit(1);
      final remote = rows.isEmpty
          ? null
          : Map<String, dynamic>.from(rows.first);
      if (pending.isEmpty) {
        if (remote == null) await _conflict(initial, null, operationIds);
        return (row: remote, retries: attempt);
      }
      // A lost response is not permission to replay an old edit over later changes.
      for (var index = operations.length - 1; index >= 0; index--) {
        final uncertain = operations[index]['attempt'] as Map?;
        if (uncertain == null) continue;
        if (_sameSnapshot(remote, uncertain['after'])) {
          await _mark([pending[index]], confirmed: true);
          operations.removeAt(index);
          pending.removeAt(index);
        } else if (!_sameSnapshot(remote, uncertain['before'])) {
          await _conflict(initial, remote, operationIds);
        }
      }
      if (pending.isEmpty) return (row: remote!, retries: attempt);
      final creation = operations
          .where((op) => op['kind'] == 'create')
          .firstOrNull;
      if (remote == null && creation == null && !legacy && !replacement) {
        await _conflict(initial, remote, operationIds);
      }
      var base = remote == null
          ? (creation == null
                ? initial
                : Task.fromJson(
                    Map<String, dynamic>.from(creation['snapshot'] as Map),
                  ))
          : taskFromRemote(remote);
      if (legacy && remote != null) {
        if (_sameContent(
          taskToRemote(initial, userId),
          taskToRemote(base, userId),
        )) {
          await _mark(pending, confirmed: true);
          return (row: remote, retries: attempt);
        }
        await _conflict(initial, remote, operationIds);
      }
      for (final op in operations) {
        if (op['kind'] == 'replace') {
          base = Task.fromJson(
            Map<String, dynamic>.from(op['snapshot'] as Map),
          );
          continue;
        }
        if (op['kind'] != 'patch') continue;
        final patch = Map<String, dynamic>.from(op['changes'] as Map);
        if (base.deletedAt != null && !patch.containsKey('deletedAt')) {
          await _conflict(initial, remote, operationIds);
        }
        base = Task.fromJson({...base.toJson(), ...patch});
      }
      final candidate = taskToRemote(base, userId);
      if (remote != null &&
          _sameContent(
            candidate,
            taskToRemote(taskFromRemote(remote), userId),
          )) {
        await _mark(pending, confirmed: true);
        await db.recordSyncRevision(
          entityId: initial.id,
          source: 'sync_confirmed',
          before: remote,
          after: remote,
          operationIds: operationIds,
        );
        return (row: remote, retries: attempt);
      }
      final remoteCounter = remote?['logical_version'] as int? ?? 0;
      candidate['logical_version'] =
          (initial.logicalVersion > remoteCounter
              ? initial.logicalVersion
              : remoteCounter) +
          1;
      candidate['device_id'] = initial.deviceId;
      candidate['updated_at'] = DateTime.now().toUtc().microsecondsSinceEpoch;
      // Persist the remote preimage before sending; it survives a process/network failure.
      await db.recordSyncRevision(
        entityId: initial.id,
        source: 'sync_attempt',
        before: remote,
        after: candidate,
        operationIds: operationIds,
      );
      await _mark(pending, attempt: {'before': remote, 'after': candidate});
      List<Map<String, dynamic>> written;
      if (remote == null) {
        try {
          written = await client.from('tasks').insert(candidate).select();
        } on PostgrestException catch (error) {
          if (error.code == '23505' && !error.message.contains('series_id')) {
            await _mark(pending);
            continue;
          }
          rethrow;
        }
      } else {
        written = await client
            .from('tasks')
            .update(candidate)
            .eq('id', initial.id)
            .eq('logical_version', remote['logical_version'])
            .eq('device_id', remote['device_id'])
            .select();
      }
      if (written.isEmpty) {
        await _mark(pending);
        continue;
      } // Concurrent write: re-read, never blindly rebase.
      final accepted = Map<String, dynamic>.from(written.single);
      await _mark(pending, confirmed: true);
      await db.recordSyncRevision(
        entityId: initial.id,
        source: 'sync_accepted',
        before: remote,
        after: accepted,
        operationIds: operationIds,
      );
      return (row: accepted, retries: attempt);
    }
    throw const SyncConcurrentWriteException();
  }

  Future<void> _mark(
    List<OutboxEntry> entries, {
    bool confirmed = false,
    Map<String, dynamic>? attempt,
  }) => db.transaction(() async {
    for (final entry in entries) {
      final payload =
          Map<String, dynamic>.from(jsonDecode(entry.payload) as Map)
            ..remove('attempt')
            ..remove('confirmed');
      if (confirmed) payload['confirmed'] = true;
      if (attempt != null) payload['attempt'] = attempt;
      await (db.update(db.outboxEntries)
            ..where((row) => row.operationId.equals(entry.operationId)))
          .write(OutboxEntriesCompanion(payload: Value(jsonEncode(payload))));
    }
  });

  Future<Never> _conflict(
    Task initial,
    Map<String, dynamic>? remote,
    List<String> ids,
  ) async {
    await db.recordSyncRevision(
      entityId: initial.id,
      source: 'sync_conflict',
      before: remote,
      after: taskToRemote(initial, client.auth.currentUser!.id),
      operationIds: ids,
    );
    throw const SyncIntentConflictException();
  }
}

bool _sameSnapshot(Map<String, dynamic>? row, dynamic other) {
  if (row == null || other == null) return row == null && other == null;
  final expected = Map<String, dynamic>.from(other as Map);
  return expected.keys.every((key) => row[key] == expected[key]);
}
