import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_request_scope.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sync_server.dart';

void main() {
  for (final entity in ['tasks', 'projects']) {
    test(
      'dispose ignores late $entity acceptance and keeps uncertain intent',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final repo = TaskRepository(db, deviceId: 'synthetic-device');
        final server = SyntheticSyncServer();
        final client = await server.client();
        final sync = SyncService(db, client);
        if (entity == 'tasks') {
          await repo.create('Synthetic task');
        } else {
          await repo.createProject('Synthetic project');
        }
        final entered = Completer<void>(), release = Completer<void>();
        server.beforeWrite = (_, _) async {
          entered.complete();
          await release.future;
        };
        final operation = sync.sync();
        await entered.future;
        final disposing = sync.dispose();
        release
            .complete(); // Models transport that cannot retract a server write.
        await disposing;
        await operation;
        final pending = await db.select(db.outboxEntries).getSingle();
        final payload = jsonDecode(pending.payload) as Map;
        expect(payload['attempt'], isNotNull);
        expect(payload['confirmed'], isNot(true));
        expect(server.receipts, isEmpty);
        await sync.sync(); // No work is restarted after disposal.
        expect(server.writes, 1);
        server.beforeWrite = null;
        final next = SyncService(db, client);
        await next.sync();
        expect(next.latest.phase, SyncPhase.current);
        expect(await db.select(db.outboxEntries).get(), isEmpty);
        expect(
          server.writes,
          1,
        ); // Lost acknowledgement is reconciled, not replayed.
        await next.dispose();
        await client.dispose();
        await db.close();
      },
    );
  }

  test(
    'account change prevents acknowledgement of an old account response',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'synthetic-device');
      await repo.create('Synthetic');
      final server = SyntheticSyncServer();
      final client = await server.client();
      final sync = SyncService(db, client);
      final entered = Completer<void>(), release = Completer<void>();
      server.beforeWrite = (_, _) async {
        entered.complete();
        await release.future;
      };
      final operation = sync.sync();
      await entered.future;
      final session = client.auth.currentSession!.toJson();
      session['user'] = {
        ...session['user'] as Map,
        'id': '00000000-0000-4000-8000-000000000099',
      };
      await client.auth.setInitialSession(jsonEncode(session));
      release.complete();
      await operation;
      expect(server.receipts, isEmpty);
      expect(await db.select(db.outboxEntries).get(), hasLength(1));
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );

  test(
    'purge after disposal fails instead of permitting local deletion',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final client = await SyntheticSyncServer().client();
      final service = SyncService(db, client);
      await service.dispose();
      await expectLater(
        service.purgeRemoteTrash(),
        throwsA(isA<SyncCancelled>()),
      );
      await client.dispose();
      await db.close();
    },
  );

  for (final cancel in [false, true]) {
    test(
      'HTTP ${cancel ? 'cancellation' : 'timeout'} stops a stalled request',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final entered = Completer<void>();
        server.listen((request) {
          entered.complete();
        });
        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'synthetic',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        final scope = SyncRequestScope(
          client,
          timeout: const Duration(milliseconds: 150),
        );
        final watch = Stopwatch()..start();
        final result = scope.send(client.from('tasks').select());
        final assertion = expectLater(
          result,
          cancel ? throwsA(isA<Exception>()) : throwsA(isA<TimeoutException>()),
        );
        await entered.future;
        if (cancel) scope.cancel();
        await assertion;
        expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
        await client.dispose();
        await server.close(force: true);
      },
    );
  }
}
