import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda_request.dart';
import 'package:deterministic_todo/services/agenda_web_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Synthetic `agenda_requests` table behind PostgREST, enough for retry.
class _Queue {
  final rows = <Map<String, Object?>>[];
  final inserted = <Map<String, Object?>>[];
  final deleted = <String>[];

  SupabaseClient client() => SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      http.Response reply(Object body) => http.Response(
        jsonEncode(body),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
      expect(request.url.pathSegments.last, 'agenda_requests');
      switch (request.method) {
        case 'GET':
          return reply(rows);
        case 'POST':
          final row = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          inserted.add(row);
          rows.add({
            ...row,
            'id': 'new${inserted.length}',
            'status': 'pending',
            'created_at': '2026-10-12T15:00:00Z',
          });
          return reply([]);
        case 'DELETE':
          final id = request.url.queryParameters['id']!.substring(3);
          deleted.add(id);
          rows.removeWhere((r) => r['id'] == id);
          return reply([]);
      }
      throw StateError('Unexpected ${request.method}');
    }),
  );
}

Map<String, Object?> _failed(String id, String error) => {
  'id': id,
  'kind': 'update',
  'status': 'failed',
  'created_at': '2026-10-12T14:00:00Z',
  'completed_at': '2026-10-12T14:01:00Z',
  'instance_key': '42@1',
  'series': true,
  'payload': {'title': 'Synthetic', 'calendar': 'cal'},
  'error': error,
};

void main() {
  test('only explicit refusals can be retried', () {
    AgendaRequest of(String status, String? error) => AgendaRequest.fromRow({
      ..._failed('r', error ?? ''),
      'status': status,
      'error': error,
    });
    expect(of('failed', 'Calendario in sola lettura.').retryable, isTrue);
    expect(of('failed', agendaUnknownOutcome).retryable, isFalse);
    expect(of('done', null).retryable, isFalse);
    expect(of('pending', null).retryable, isFalse);
  });

  test('the SQL expiry message matches the client constant', () async {
    final sql = await File(
      'supabase/migrations/202610050001_agenda_requests.sql',
    ).readAsString();
    expect(sql, contains("'$agendaUnknownOutcome'"));
  });

  test(
    'Riprova queues an identical new request and drops the notice',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final queue = _Queue()
        ..rows.add(_failed('r1', 'Calendario in sola lettura.'));
      final service = WebAgendaService(db, queue.client());
      await service.retryRequest('r1'); // Unknown before the first read.
      expect(queue.inserted, isEmpty);
      await service.dismissRequest('none'); // Loads the queue.
      expect(service.failedRequests.single.id, 'r1');

      await service.retryRequest('r1');
      expect(queue.inserted.single, {
        'kind': 'update',
        'instance_key': '42@1',
        'series': true,
        'payload': {'title': 'Synthetic', 'calendar': 'cal'},
      });
      expect(queue.deleted, contains('r1'));
      expect(service.failedRequests, isEmpty);
    },
  );

  test('an unknown outcome is never sent again', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = _Queue()..rows.add(_failed('r2', agendaUnknownOutcome));
    final service = WebAgendaService(db, queue.client());
    await service.dismissRequest('none');
    await service.retryRequest('r2');
    expect(queue.inserted, isEmpty);
    expect(service.failedRequests.single.id, 'r2');
  });
}
