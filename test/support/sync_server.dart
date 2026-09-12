import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Content is always synthetic; models PostgREST paging, uniqueness and CAS.
class SyntheticSyncServer {
  final tables = <String, Map<String, Map<String, dynamic>>>{
    'tasks': {},
    'projects': {},
    'project_sections': {},
    'purged_entities': {},
  };
  final receipts = <String, Map<String, dynamic>>{};
  int pageCap = 200;
  int writes = 0;
  int pages = 0;
  bool fingerprints = false;
  bool overview = false;
  int overviewReads = 0;
  int fingerprintReads = 0;
  bool failReceipt = false;
  final loseResponse = <String>{};
  Future<void> Function(String table, String id)? beforeWrite;
  Future<void> Function(String table)? beforeRead;

  List<Map<String, String>> taskFingerprints() {
    final signatures = <String, StringBuffer>{};
    final rows = tables['tasks']!.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    for (final row in rows) {
      final bucket = (row['id'] as String).substring(0, 2);
      signatures
          .putIfAbsent(bucket, StringBuffer.new)
          .write('${row['id']}:${row['logical_version']}:${row['device_id']};');
    }
    return [
      for (final e in signatures.entries)
        {
          'bucket': e.key,
          'fingerprint': sha256
              .convert(utf8.encode(e.value.toString()))
              .toString(),
        },
    ];
  }

  String tableDigest(String table) {
    final rows = tables[table]!.values.toList();
    final values = [
      for (final row in rows)
        table == 'purged_entities'
            ? 'purged:${row['entity_type']}:${row['entity_id']};'
            : '${row['id']}:${row['logical_version']}:${row['device_id']};',
    ]..sort();
    return sha256.convert(utf8.encode(values.join())).toString();
  }

  Future<SupabaseClient> client() async {
    final client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response reply(Object? body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        final table = request.url.pathSegments.last;
        if (table == 'todo_sync_overview_v1') {
          if (!overview) {
            return reply({'code': 'PGRST202', 'message': 'RPC missing'}, 404);
          }
          overviewReads++;
          return reply({
            'schema': 1,
            'tasks': taskFingerprints(),
            for (final name in [
              'projects',
              'project_sections',
              'purged_entities',
            ])
              name: tableDigest(name),
          });
        }
        if (table == 'todo_task_fingerprints_v1') {
          if (!fingerprints) {
            return reply({'code': 'PGRST202', 'message': 'RPC missing'}, 404);
          }
          fingerprintReads++;
          return reply(taskFingerprints());
        }
        if (table == 'sync_operations') {
          if (failReceipt) throw StateError('synthetic receipt failure');
          for (final raw in jsonDecode(request.body) as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            if (!const {'upsert', 'delete'}.contains(row['operation'])) {
              return reply({
                'code': '23514',
                'message': 'invalid operation',
              }, 400);
            }
            receipts[row['operation_id'] as String] = Map<String, dynamic>.from(
              row as Map,
            );
          }
          return reply([]);
        }
        final data = tables[table];
        if (data == null) {
          throw StateError('Unexpected synthetic endpoint $table');
        }
        final q = request.url.queryParameters;
        final filter = q['id'];
        if (request.method == 'GET') {
          pages++;
          await beforeRead?.call(table);
          var rows = data.values.toList()
            ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
          if (q['order']?.startsWith('id.desc') == true) {
            rows = rows.reversed.toList();
          }
          if (filter?.startsWith('eq.') == true) {
            rows = rows.where((r) => r['id'] == filter!.substring(3)).toList();
          }
          if (filter?.startsWith('gt.') == true) {
            rows = rows
                .where(
                  (r) =>
                      (r['id'] as String).compareTo(filter!.substring(3)) > 0,
                )
                .toList();
          }
          final filters = request.url.queryParametersAll['id'] ?? [];
          for (final condition in filters) {
            if (condition.startsWith('gte.')) {
              rows = rows
                  .where(
                    (r) =>
                        (r['id'] as String).compareTo(condition.substring(4)) >=
                        0,
                  )
                  .toList();
            } else if (condition.startsWith('lt.')) {
              rows = rows
                  .where(
                    (r) =>
                        (r['id'] as String).compareTo(condition.substring(3)) <
                        0,
                  )
                  .toList();
            } else if (condition.startsWith('gt.')) {
              rows = rows
                  .where(
                    (r) =>
                        (r['id'] as String).compareTo(condition.substring(3)) >
                        0,
                  )
                  .toList();
            }
          }
          final requested = int.tryParse(q['limit'] ?? '') ?? pageCap;
          return reply(
            rows.take(requested < pageCap ? requested : pageCap).toList(),
          );
        }
        final candidate = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map,
        );
        final id = candidate['id'] as String;
        await beforeWrite?.call(table, id);
        if (request.method == 'POST' && data.containsKey(id)) {
          return reply({'code': '23505', 'message': 'duplicate id'}, 409);
        }
        if (request.method == 'PATCH') {
          final old = data[id];
          if (old == null ||
              q['logical_version'] != 'eq.${old['logical_version']}' ||
              q['device_id'] != 'eq.${old['device_id']}') {
            return reply([]);
          }
        }
        writes++;
        data[id] = candidate;
        if (loseResponse.contains(id)) {
          throw StateError('synthetic response lost');
        }
        return reply([candidate]);
      }),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'synthetic-token',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': '00000000-0000-4000-8000-000000000001',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-09-11T00:00:00Z',
        },
      }),
    );
    return client;
  }
}
