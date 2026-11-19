import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart' show isBriefSyncRetry;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/sync_server.dart';

/// Distinct from every [syncRetryDelay] step, and long enough that no retry
/// timer fires while a test runs: each check below is started explicitly.
const _fast = Duration(seconds: 7);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late SyntheticSyncServer server;
  late DateTime now;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = SyntheticSyncServer()
      ..overview = true
      ..contentFingerprints = true;
    now = DateTime.utc(2026, 11, 19, 10);
  });
  tearDown(() => db.close());

  void failAll() => server.onRequest = (_) {
    throw http.ClientException('synthetic wake');
  };

  Future<SyncService> service() async {
    final sync = SyncService(db, await server.client())
      ..fastRetryDelay = _fast
      ..clock = () => now;
    return sync;
  }

  Duration retryGap(SyncService sync) =>
      sync.latest.retryAt!.difference(sync.latest.lastFailure!);

  test('outside the window failures climb the ordinary backoff', () async {
    final sync = await service();
    failAll();
    final gaps = <Duration>[];
    for (var i = 0; i < 3; i++) {
      await sync.sync();
      gaps.add(retryGap(sync));
    }
    expect(sync.inFastRecovery, isFalse);
    expect(gaps, [syncRetryDelay(0), syncRetryDelay(1), syncRetryDelay(2)]);
    await sync.dispose();
    await sync.client.dispose();
  });

  test('after a network change failures retry at the short step, '
      'then the backoff resumes from its first step', () async {
    final sync = await service();
    failAll();
    sync.networkChangedForTesting();
    await sync.sync(); // Joins the check started by the network event.
    expect(sync.inFastRecovery, isTrue);
    expect(retryGap(sync), _fast);
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 3));
      await sync.sync();
      expect(retryGap(sync), _fast, reason: 'failure ${i + 2}');
    }
    expect(sync.latest.consecutiveFailures, 5);

    now = now.add(sync.fastRecoveryWindow);
    expect(sync.inFastRecovery, isFalse);
    await sync.sync();
    expect(retryGap(sync), syncRetryDelay(0));
    await sync.sync();
    expect(retryGap(sync), syncRetryDelay(1));
    await sync.dispose();
    await sync.client.dispose();
  });

  test(
    'a return from pause opens the window; a focus alone does not',
    () async {
      final sync = await service();
      sync.resume(); // Never paused: only a focus.
      expect(sync.inFastRecovery, isFalse);
      sync.pause();
      expect(sync.inFastRecovery, isFalse);
      failAll();
      sync.resume();
      expect(sync.inFastRecovery, isTrue);
      now = now.add(sync.fastRecoveryWindow - const Duration(seconds: 1));
      expect(sync.inFastRecovery, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(sync.inFastRecovery, isFalse);
      await sync.dispose();
      await sync.client.dispose();
    },
  );

  test(
    'a success closes the failure streak and restarts the backoff',
    () async {
      final sync = await service();
      failAll();
      await sync.sync();
      await sync.sync();
      expect(retryGap(sync), syncRetryDelay(1));
      server.onRequest = null;
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      failAll();
      await sync.sync();
      expect(retryGap(sync), syncRetryDelay(0));
      await sync.dispose();
      await sync.client.dispose();
    },
  );

  test('retries a second apart stay calm however many they are', () {
    final failedAt = DateTime.utc(2026, 11, 19, 10);
    SyncSnapshot failure(int count, Duration gap) => SyncSnapshot(
      SyncPhase.error,
      lastFailure: failedAt,
      retryAt: failedAt.add(gap),
      consecutiveFailures: count,
    );
    expect(isBriefSyncRetry(failure(12, const Duration(seconds: 1))), isTrue);
    expect(isBriefSyncRetry(failure(3, const Duration(seconds: 10))), isTrue);
    expect(isBriefSyncRetry(failure(4, const Duration(seconds: 30))), isFalse);
  });

  group('remote change latency', () {
    const localDevice = 'device-local';
    const otherDevice = 'device-other';

    Future<void> storeDeviceId() => db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'device_id', value: localDevice),
        );

    late Task template;

    setUp(() async {
      final source = AppDatabase.forTesting(NativeDatabase.memory());
      await TaskRepository(source, deviceId: otherDevice).create('Synthetic');
      template = await source.select(source.tasks).getSingle();
      await source.close();
    });

    Map<String, dynamic> row(
      String id, {
      required DateTime updatedAt,
      String device = otherDevice,
    }) => {
      ...taskToRemote(template, '00000000-0000-4000-8000-000000000001'),
      'id': id,
      'logical_version': 5,
      'device_id': device,
      'updated_at': updatedAt.microsecondsSinceEpoch,
    };

    test('a Realtime change from another device is measured', () async {
      await storeDeviceId();
      final sync = await service();
      final id = '00000000-0000-4000-8000-0000000000a1';
      server.tables['tasks']![id] = row(
        id,
        updatedAt: now.subtract(const Duration(milliseconds: 850)),
      );
      await sync.pullRealtimeChangesForTesting('tasks', [id]);
      final latency = sync.remoteLatency.value!;
      expect(latency.path, RemoteChangePath.realtime);
      expect(latency.count, 1);
      expect(latency.medianMs, 850);
      expect(latency.maxMs, 850);
      expect(latency.ignored, 0);
      expect(latency.diagnosticFields.keys, {
        'path',
        'count',
        'median_ms',
        'max_ms',
        'ignored',
        'reopen_count',
        'reopen_median_ms',
      });
      await sync.dispose();
      await sync.client.dispose();
    });

    test('a full check measures only news from other devices', () async {
      await storeDeviceId();
      final sync = await service();
      String id(int n) => '00000000-0000-4000-8000-0000000000${n}0';
      server.tables['tasks']!
        ..[id(1)] = row(
          id(1),
          updatedAt: now.subtract(const Duration(seconds: 1)),
        )
        ..[id(2)] = row(
          id(2),
          updatedAt: now.subtract(const Duration(seconds: 3)),
        )
        ..[id(3)] = row(
          id(3),
          updatedAt: now.subtract(const Duration(seconds: 2)),
        )
        // Own echo, clock skew and stale history are not latency samples.
        ..[id(4)] = row(
          id(4),
          updatedAt: now.subtract(const Duration(seconds: 1)),
          device: localDevice,
        )
        ..[id(5)] = row(id(5), updatedAt: now.add(const Duration(seconds: 4)))
        ..[id(6)] = row(
          id(6),
          updatedAt: now.subtract(const Duration(days: 3)),
        );
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      final latency = sync.remoteLatency.value!;
      expect(latency.path, RemoteChangePath.full);
      expect(latency.count, 3);
      expect(latency.medianMs, 2000);
      expect(latency.maxMs, 3000);
      expect(latency.ignored, 2);

      // Equal versions re-read later are not news: the figure stays put.
      now = now.add(const Duration(minutes: 1));
      await sync.repairAlignment();
      expect(identical(sync.remoteLatency.value, latency), isTrue);
      await sync.dispose();
      await sync.client.dispose();
    });

    test(
      'changes sent while the app was closed count from the reopening',
      () async {
        await storeDeviceId();
        final sync = await service();
        sync.pause();
        final reopened = now;
        sync.resume(); // Back to the foreground: openedAt = now.
        String id(int n) => '00000000-0000-4000-8000-0000000000${n}b';
        server.tables['tasks']!
          // Sent four minutes before reopening: catch-up, not delay.
          ..[id(1)] = row(
            id(1),
            updatedAt: reopened.subtract(const Duration(minutes: 4)),
          )
          // Sent after reopening: live delay.
          ..[id(2)] = row(
            id(2),
            updatedAt: reopened.add(const Duration(milliseconds: 100)),
          );
        now = reopened.add(const Duration(milliseconds: 600));
        await sync.sync(freshSnapshot: true);
        final latency = sync.remoteLatency.value!;
        expect(latency.reopenCount, 1);
        expect(latency.reopenMedianMs, 600);
        expect(latency.count, 1);
        expect(latency.medianMs, 500);
        expect(latency.ignored, 0);
        await sync.dispose();
        await sync.client.dispose();
      },
    );

    test('summaries tolerate malformed stamps and report nothing for '
        'local rows', () {
      final at = DateTime.utc(2026, 11, 19, 10);
      final samples = RemoteLatencySamples(localDevice)
        ..add([
          {'device_id': localDevice, 'updated_at': 1},
        ], at);
      expect(samples.summary(RemoteChangePath.full, at), isNull);
      samples.add([
        {'device_id': otherDevice, 'updated_at': 'not a number'},
        {'device_id': otherDevice},
        {
          'device_id': otherDevice,
          'updated_at': '${at.microsecondsSinceEpoch - 4000}',
        },
        {
          'device_id': otherDevice,
          'updated_at': (at.microsecondsSinceEpoch - 2000).toDouble(),
        },
      ], at);
      final summary = samples.summary(RemoteChangePath.realtime, at)!;
      expect(summary.count, 2);
      expect(summary.medianMs, 3);
      expect(summary.maxMs, 4);
      expect(summary.ignored, 2);
    });
  });
}
