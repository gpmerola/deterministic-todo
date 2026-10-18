import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/sync_server.dart';

const _dnsFailure =
    "Failed host lookup: 'synthetic.invalid' "
    '(OS Error: No address associated with hostname, errno = 7)';

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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = SyntheticSyncServer()
      ..overview = true
      ..contentFingerprints = true;
  });
  tearDown(() => db.close());

  /// The next [count] requests fail with [message] before reaching the server.
  void failNext(int count, [String message = 'synthetic wake']) {
    var left = count;
    server.onRequest = (_) {
      if (left <= 0) return;
      left--;
      throw http.ClientException(message);
    };
  }

  test('a DNS failure is classified apart from other network errors', () {
    expect(safeSyncErrorClass(http.ClientException(_dnsFailure)), 'dns');
    expect(isDnsSyncError(http.ClientException(_dnsFailure)), isTrue);
    expect(safeSyncErrorClass(http.ClientException('reset')), 'network');
    expect(isTransientSyncError(http.ClientException(_dnsFailure)), isTrue);
    // The message is only inspected, never part of the stored code.
    expect(
      safeSyncErrorCode(http.ClientException(_dnsFailure)),
      isNot(contains('synthetic.invalid')),
    );
  });

  test('network errors read as plain Italian, others keep their code', () {
    final retryAt = DateTime(2026, 10, 18, 12, 0, 5);
    expect(
      syncErrorText(
        SyncSnapshot(
          SyncPhase.error,
          error: 'Rete ClientException',
          errorClass: 'network',
          retryAt: retryAt,
        ),
      ),
      'Nessuna connessione · riprovo alle 12:00:05',
    );
    expect(
      syncErrorText(
        const SyncSnapshot(
          SyncPhase.error,
          error: 'Rete ClientException',
          errorClass: 'network',
        ),
      ),
      'Nessuna connessione, riprovo appena torna la rete',
    );
    expect(
      syncErrorText(
        const SyncSnapshot(
          SyncPhase.error,
          error: 'Rete ClientException',
          errorClass: 'dns',
        ),
      ),
      'La rete non trova il server: controlla VPN o Wi-Fi',
    );
    expect(
      syncErrorText(
        const SyncSnapshot(
          SyncPhase.error,
          error: 'Supabase 42501',
          errorClass: 'supabase',
        ),
      ),
      'Errore · Supabase 42501',
    );
  });

  test('a failed check exposes the error class to the interface', () async {
    final client = await server.client();
    final sync = SyncService(db, client);
    failNext(1, _dnsFailure);
    await sync.sync();
    expect(sync.latest.phase, SyncPhase.error);
    expect(sync.latest.errorClass, 'dns');
    await sync.dispose();
    await client.dispose();
  });

  test('network back checks now instead of waiting for the backoff', () async {
    final client = await server.client();
    final sync = SyncService(db, client);
    failNext(3);
    await sync.sync();
    await sync.sync();
    await sync.sync(); // Third failure: next retry 10 s away.
    expect(sync.latest.phase, SyncPhase.error);
    expect(sync.latest.consecutiveFailures, 3);
    final clock = Stopwatch()..start();
    sync.networkChangedForTesting();
    await sync.sync(); // Joins the check started by the network event.
    expect(sync.latest.phase, SyncPhase.current);
    expect(sync.latest.retryAt, isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));

    // The backoff restarted: a new failure retries after the first step.
    failNext(1);
    await sync.sync();
    expect(
      sync.latest.retryAt!.difference(sync.latest.lastFailure!),
      syncRetryDelay(0),
    );
    await sync.dispose();
    await client.dispose();
  });

  test('a hung first check gives up early; the retry waits longer', () async {
    final client = await server.client();
    final sync = SyncService(db, client)
      ..firstCheckTimeout = const Duration(milliseconds: 150);
    server.latency = const Duration(milliseconds: 400);
    final clock = Stopwatch()..start();
    await sync.sync();
    expect(clock.elapsed, lessThan(const Duration(milliseconds: 380)));
    expect(sync.latest.phase, SyncPhase.error);
    expect(sync.latest.errorClass, 'timeout');
    await sync.sync(); // After a failure the normal limit applies.
    expect(sync.latest.phase, SyncPhase.current);
    await sync.dispose();
    await client.dispose();
  });

  test(
    'pausing retries edits left by a transient failure',
    () async {
      final client = await server.client();
      final sync = SyncService(db, client);
      final repo = TaskRepository(db, deviceId: 'synthetic-device');
      sync.start();
      final id = await repo.create('Sintetica in attesa');
      failNext(1 << 20);
      await sync.sync(pullAll: false);
      expect(sync.latest.retryAt, isNotNull);
      expect(await db.select(db.outboxEntries).get(), isNotEmpty);
      expect(sync.hasUnsentWork, isTrue); // The Web page-close guard asks.

      server.onRequest = null; // The network works again.
      sync.pause();
      while ((await db.select(db.outboxEntries).get()).isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(server.tables['tasks']!.containsKey(id), isTrue);
      while (sync.hasUnsentWork) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await sync.dispose();
      await client.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
