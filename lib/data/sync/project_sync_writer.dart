import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'task_sync_writer.dart';

bool isProjectOperation(OutboxEntry entry) =>
    entry.operation == 'projects' || entry.operation == 'project_sections';

Map<String, dynamic> normalizeProject(Map<String, dynamic> row) => {
  for (final e in row.entries)
    e.key: e.key == 'is_archived' || e.key == 'is_favorite'
        ? e.value == true || e.value == 1
        : e.value,
};

bool _same(
  Map<String, dynamic>? a,
  Map<String, dynamic>? b, {
  bool contentOnly = false,
}) {
  if (a == null || b == null) return a == null && b == null;
  final left = normalizeProject(a);
  final right = normalizeProject(b);
  return left.entries.every(
    (e) =>
        (contentOnly &&
            const {
              'user_id',
              'logical_version',
              'device_id',
            }.contains(e.key)) ||
        e.value == right[e.key],
  );
}

class ProjectSyncWriter {
  ProjectSyncWriter(this.db, this.client);
  final AppDatabase db;
  final SupabaseClient client;

  Future<Map<String, dynamic>> upload(List<OutboxEntry> entries) async {
    final first = entries.first;
    final table = first.operation;
    if (!isProjectOperation(first)) throw ArgumentError('Invalid entity table');
    final payloads = entries
        .map((e) => jsonDecode(e.payload) as Map<String, dynamic>)
        .toList();
    final ids = entries.map((e) => e.operationId).toList();
    Future<void> conflict(Map<String, dynamic>? remote) async {
      await db.recordSyncRevision(
        entityId: first.entityId,
        entityType: table,
        source: 'sync_conflict',
        before: remote,
        after: Map<String, dynamic>.from(payloads.last['snapshot'] as Map),
        operationIds: ids,
      );
      throw const SyncIntentConflictException();
    }

    for (var retry = 0; retry < 4; retry++) {
      final rows = await client
          .from(table)
          .select()
          .eq('id', first.entityId)
          .limit(1);
      final remote = rows.firstOrNull;
      final active = <int>[];
      for (var i = 0; i < entries.length; i++) {
        final op = payloads[i];
        if (op['confirmed'] == true) continue;
        final attempt = op['attempt'] as Map?;
        if (attempt != null) {
          if (_same(
            remote,
            Map<String, dynamic>.from(attempt['after'] as Map),
          )) {
            op['confirmed'] = true;
            await _save(entries[i], op);
            continue;
          }
          if (!_same(
            remote,
            attempt['before'] == null
                ? null
                : Map<String, dynamic>.from(attempt['before'] as Map),
          )) {
            await conflict(remote);
          }
        }
        active.add(i);
      }
      if (active.isEmpty) {
        if (remote == null) await conflict(remote);
        return remote!;
      }
      var candidate = remote == null ? null : Map<String, dynamic>.from(remote);
      for (final i in active) {
        final op = payloads[i];
        final snapshot = normalizeProject(
          Map<String, dynamic>.from(op['snapshot'] as Map),
        );
        switch (op['kind']) {
          case 'create':
            candidate ??= snapshot;
          case 'replace':
            candidate = snapshot;
          case 'legacy':
            if (candidate != null &&
                !_same(candidate, snapshot, contentOnly: true)) {
              await conflict(remote);
            }
            candidate ??= snapshot;
          case 'patch':
            if (candidate == null) await conflict(remote);
            final changes = normalizeProject(
              Map<String, dynamic>.from(op['changes'] as Map),
            );
            if (candidate!['is_archived'] == true &&
                changes['is_archived'] != false) {
              await conflict(remote);
            }
            candidate.addAll(changes);
          default:
            await conflict(remote);
        }
      }
      candidate!['user_id'] = client.auth.currentUser!.id;
      if (remote != null && _same(candidate, remote, contentOnly: true)) {
        for (final i in active) {
          payloads[i]['confirmed'] = true;
          await _save(entries[i], payloads[i]);
        }
        return remote;
      }
      final local = Map<String, dynamic>.from(payloads.last['snapshot'] as Map);
      final remoteVersion = remote?['logical_version'] as int? ?? 0;
      final localVersion = local['logical_version'] as int;
      candidate['logical_version'] =
          (remoteVersion > localVersion ? remoteVersion : localVersion) + 1;
      candidate['device_id'] = local['device_id'];
      for (final i in active) {
        payloads[i]['attempt'] = {'before': remote, 'after': candidate};
        await _save(entries[i], payloads[i]);
      }
      await db.recordSyncRevision(
        entityId: first.entityId,
        entityType: table,
        source: 'sync_attempt',
        before: remote,
        after: candidate,
        operationIds: ids,
      );
      List<Map<String, dynamic>> written;
      try {
        written = remote == null
            ? await client.from(table).insert(candidate).select()
            : await client
                  .from(table)
                  .update(candidate)
                  .eq('id', first.entityId)
                  .eq('logical_version', remote['logical_version'])
                  .eq('device_id', remote['device_id'])
                  .select();
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        written = [];
      }
      if (written.isEmpty) {
        for (final i in active) {
          payloads[i].remove('attempt');
          await _save(entries[i], payloads[i]);
        }
        continue;
      }
      final accepted = written.single;
      if (!_same(accepted, candidate)) {
        throw const SyncConcurrentWriteException();
      }
      for (final i in active) {
        payloads[i]['confirmed'] = true;
        await _save(entries[i], payloads[i]);
      }
      await db.recordSyncRevision(
        entityId: first.entityId,
        entityType: table,
        source: 'sync_accepted',
        before: remote,
        after: accepted,
        operationIds: ids,
      );
      return accepted;
    }
    throw const SyncConcurrentWriteException();
  }

  Future<void> _save(OutboxEntry e, Map<String, dynamic> payload) =>
      (db.update(db.outboxEntries)
            ..where((r) => r.operationId.equals(e.operationId)))
          .write(OutboxEntriesCompanion(payload: Value(jsonEncode(payload))));
}
