import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

class _CountingRepository extends TaskRepository {
  _CountingRepository(super.db, {required super.deviceId});
  int watchAllCalls = 0;

  @override
  Stream<List<Task>> watchAll() {
    watchAllCalls++;
    return super.watchAll();
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('pausing flushes an edit queued behind the active cycle', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db, deviceId: 'synthetic-device');
    final server = SyntheticSyncServer();
    final client = await server.client();
    final sync = SyncService(db, client);
    await repo.create('Prima');
    final entered = Completer<void>(), release = Completer<void>();
    server.beforeWrite = (_, _) async {
      if (entered.isCompleted) return;
      entered.complete();
      await release.future;
    };
    final first = sync.sync();
    await entered.future;
    final lateId = await repo.create('Poco prima della chiusura');
    unawaited(sync.sync(pullAll: false)); // As the outbox listener does.
    sync.pause();
    release.complete();
    await first;
    expect(server.tables['tasks']!.containsKey(lateId), isTrue);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    await sync.dispose();
    await client.dispose();
    await db.close();
  });

  test('resume without a pause does not restart work', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final server = SyntheticSyncServer();
    final client = await server.client();
    final sync = SyncService(db, client);
    sync.resume();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.pages, 0);
    expect(sync.latest.phase, SyncPhase.disabled);
    await sync.dispose();
    await client.dispose();
    await db.close();
  });

  test('only a first transient retry is presented as non-alarming', () {
    final retryAt = DateTime.utc(2026, 9, 25, 18, 30);
    expect(
      isBriefSyncRetry(
        SyncSnapshot(SyncPhase.error, retryAt: retryAt, consecutiveFailures: 1),
      ),
      isTrue,
    );
    expect(
      isBriefSyncRetry(
        SyncSnapshot(SyncPhase.error, retryAt: retryAt, consecutiveFailures: 3),
      ),
      isFalse,
    );
    expect(
      isBriefSyncRetry(
        const SyncSnapshot(SyncPhase.error, error: 'Supabase 42501'),
      ),
      isFalse,
    );
    expect(
      isBriefSyncRetry(SyncSnapshot(SyncPhase.current, retryAt: retryAt)),
      isFalse,
    );
  });

  testWidgets('typing in search does not reload the whole archive', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _CountingRepository(db, deviceId: 'test-device');
    await repository.create('Alfa');
    await repository.create('Beta');
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            root = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    unawaited(
      showSearch<void>(
        context: root,
        delegate: TaskSearchDelegate(
          repository,
          onNavigate: (_) {},
          onCreate: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (final text in ['A', 'Al', 'Alf', 'Alfa']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Alfa'), findsWidgets);
    expect(find.text('Beta'), findsNothing);
    expect(repository.watchAllCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
