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

  test('pausing cancels a read-only check instead of failing later', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final server = SyntheticSyncServer();
    final client = await server.client();
    final sync = SyncService(db, client);
    final entered = Completer<void>(), release = Completer<void>();
    server.beforeRead = (table) async {
      if (table != 'projects' || entered.isCompleted) return;
      entered.complete();
      await release.future;
      throw StateError('synthetic transport cut after backgrounding');
    };
    final check = sync.sync();
    await entered.future;
    sync.pause();
    release.complete();
    await check;
    expect(sync.latest.phase, isNot(SyncPhase.error));
    expect(sync.latest.lastFailure, isNull);
    await sync.dispose();
    await client.dispose();
    await db.close();
  });

  test('pausing never cancels an upload already in flight', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db, deviceId: 'synthetic-device');
    final server = SyntheticSyncServer();
    final client = await server.client();
    final sync = SyncService(db, client);
    final id = await repo.create('In invio');
    final entered = Completer<void>(), release = Completer<void>();
    server.beforeWrite = (_, _) async {
      if (entered.isCompleted) return;
      entered.complete();
      await release.future;
    };
    final upload = sync.sync(pullAll: false);
    await entered.future;
    sync.pause();
    release.complete();
    await upload;
    expect(server.tables['tasks']!.containsKey(id), isTrue);
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

  testWidgets('sync pauses in background without any frame being built', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final server = SyntheticSyncServer();
    final client = await tester.runAsync(server.client);
    final sync = SyncService(db, client!);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final listener = bindSyncToLifecycle(sync);
    expect(sync.isPaused, isTrue); // Started in background.
    listener.dispose();

    final other = SyncService(db, client);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final live = bindSyncToLifecycle(other);
    expect(other.isPaused, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(other.isPaused, isFalse); // Transient interruption.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(other.isPaused, isTrue);
    live.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() async {
      await sync.dispose();
      await other.dispose();
      await client.dispose();
      await db.close();
    });
  });

  test('only real background states suspend sync', () {
    expect(isBackgroundLifecycle(AppLifecycleState.hidden), isTrue);
    expect(isBackgroundLifecycle(AppLifecycleState.paused), isTrue);
    expect(isBackgroundLifecycle(AppLifecycleState.detached), isTrue);
    expect(isBackgroundLifecycle(AppLifecycleState.inactive), isFalse);
    expect(isBackgroundLifecycle(AppLifecycleState.resumed), isFalse);
    expect(isBackgroundLifecycle(null), isFalse);
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
