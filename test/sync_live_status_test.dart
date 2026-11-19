import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/ui/sync_live_status.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sync_server.dart';

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it');
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('the relative age uses coarse, truthful steps', () {
    final now = DateTime(2026, 11, 19, 10, 30);
    expect(syncAgeLabel(null, now), 'mai aggiornato');
    expect(
      syncAgeLabel(now.subtract(const Duration(seconds: 4)), now),
      'aggiornato adesso',
    );
    expect(
      syncAgeLabel(now.subtract(const Duration(seconds: 42)), now),
      'aggiornato 42 s fa',
    );
    expect(
      syncAgeLabel(now.subtract(const Duration(minutes: 7)), now),
      'aggiornato 7 min fa',
    );
    expect(
      syncAgeLabel(DateTime(2026, 11, 19, 8, 5), now),
      'aggiornato alle 08:05',
    );
    expect(
      syncAgeLabel(DateTime(2026, 11, 18, 22, 5), now),
      'aggiornato alle 18 nov 22:05',
    );
    // Ten seconds while the age is under a minute, then thirty.
    expect(
      syncAgeRefresh(now.subtract(const Duration(seconds: 5)), now),
      const Duration(seconds: 10),
    );
    expect(
      syncAgeRefresh(now.subtract(const Duration(minutes: 5)), now),
      const Duration(seconds: 30),
    );
    expect(syncAgeRefresh(null, now), const Duration(seconds: 30));
  });

  test('channel and latency labels carry no content', () {
    expect(realtimeLinkLabel(RealtimeLink.connected), 'Live');
    expect(realtimeLinkLabel(RealtimeLink.connecting), 'Live in collegamento…');
    expect(realtimeLinkLabel(RealtimeLink.disconnected), 'Live non collegato');
    final at = DateTime(2026, 11, 19, 10, 30, 5);
    expect(
      remoteLatencyLabel(
        RemoteChangeLatency(
          path: RemoteChangePath.realtime,
          count: 1,
          medianMs: 640,
          maxMs: 640,
          ignored: 0,
          measuredAt: at,
        ),
      ),
      '640 ms · via Realtime · 10:30:05',
    );
    expect(
      remoteLatencyLabel(
        RemoteChangeLatency(
          path: RemoteChangePath.full,
          count: 3,
          medianMs: 1200,
          maxMs: 4100,
          ignored: 1,
          measuredAt: at,
        ),
      ),
      '1200 ms · max 4100 ms su 3 · via controllo completo · 10:30:05',
    );
  });

  test('pull to sync does nothing without a service or an account', () async {
    await pullToSync(null);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final sync = SyncService(db, client);
    await pullToSync(sync);
    expect(sync.latest.phase, SyncPhase.disabled);
    await sync.dispose();
    await client.dispose();
    await db.close();
  });

  test(
    'pull to sync runs a fresh check and never waits past its limit',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final server = SyntheticSyncServer();
      final client = await server.client();
      final sync = SyncService(db, client);
      await pullToSync(sync);
      expect(sync.latest.phase, SyncPhase.current);
      final before = server.requests;

      server.latency = const Duration(milliseconds: 1500);
      final clock = Stopwatch()..start();
      await pullToSync(sync, limit: const Duration(milliseconds: 100));
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 1200)));
      await sync.sync(); // The check carried on in background.
      expect(server.requests, greaterThan(before));
      expect(sync.latest.phase, SyncPhase.current);
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );

  testWidgets('task lists offer pull to refresh only with sync', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'synthetic-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('pull-to-sync')), findsNothing);

    final server = SyntheticSyncServer();
    final client = (await tester.runAsync(server.client))!;
    final sync = SyncService(db, client);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      TodoApp(repository: repository, syncClient: client, syncService: sync),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('pull-to-sync')), findsOneWidget);
    // The empty Today list still answers the gesture.
    expect(find.byKey(const ValueKey('empty-pull-today')), findsOneWidget);
    expect(server.requests, 0);
    await tester.fling(
      find.byKey(const ValueKey('empty-pull-today')),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(server.requests, greaterThan(0)); // Started by the gesture.
    await tester.runAsync(() => sync.sync());
    expect(sync.latest.phase, SyncPhase.current);
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() async {
      await sync.dispose();
      await client.dispose();
      await db.close();
    });
  });
}
