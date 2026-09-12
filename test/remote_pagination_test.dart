import 'dart:convert';

import 'package:deterministic_todo/data/sync/paged_remote.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sync_server.dart';

void main() {
  test(
    'keyset scan returns every UUID once with the real SDK ordering',
    () async {
      final server = SyntheticSyncServer()..pageCap = 200;
      for (var i = 0; i < 426; i++) {
        final id = '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
        server.tables['tasks']![id] = {'id': id};
      }
      final client = await server.client();
      addTearDown(client.dispose);
      final scope = SyncRequestScope(client);
      final pages = await remotePages(
        client,
        'tasks',
        pageSize: 200,
        scope: scope,
      ).toList();
      final ids = pages.expand((p) => p).map((r) => r['id']).toList();
      expect(ids, server.tables['tasks']!.keys.toList());
      expect(ids.toSet().length, ids.length);
      expect(scope.pullDiagnostics, {
        'pull_pages': 4,
        'pulled_rows': 426,
        'pull_table': 'tasks',
      });
    },
  );

  for (final bad in ['descending', 'overlap', 'wrong_bucket']) {
    test('rejects $bad before applying the invalid page', () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['order'], 'id.asc.nullslast');
          calls++;
          final ids = switch (bad) {
            'descending' => ['aa02', 'aa01'],
            'wrong_bucket' => ['ab01'],
            _ => calls == 1 ? ['aa01', 'aa02'] : ['aa02', 'aa03'],
          };
          return http.Response(
            jsonEncode([
              for (final id in ids) {'id': id},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final accepted = <String>[];
      await expectLater(() async {
        await for (final page in remotePages(client, 'tasks', idPrefix: 'aa')) {
          accepted.addAll(page.map((r) => r['id'] as String));
        }
      }, throwsA(isA<SyncPaginationException>()));
      expect(accepted, bad == 'overlap' ? ['aa01', 'aa02'] : isEmpty);
      expect(safeSyncErrorClass(const SyncPaginationException()), 'pagination');
      expect(isTransientSyncError(const SyncPaginationException()), isFalse);
    });
  }
}
