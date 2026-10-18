import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/realtime_server.dart';
import 'support/sync_server.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  /// Resumes after a pause whose Realtime `phx_leave` is never acknowledged
  /// and returns how long the first server check took to start.
  Future<Duration> resumeLatency({required bool answerLeave}) async {
    final realtime = SyntheticRealtimeServer()..answerLeave = answerLeave;
    await realtime.start();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final server = SyntheticSyncServer()
      ..overview = true
      ..contentFingerprints = true;
    final client = await server.client(url: realtime.url);
    final sync = SyncService(db, client);
    // Foreground with a live channel.
    sync
      ..pause()
      ..resume();
    await sync.sync();
    while (realtime.joins == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));

    sync.pause(); // The leave is sent and, here, never answered.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final checked = Completer<void>();
    server.onRequest = (name) {
      if (name.startsWith('todo_sync_overview') && !checked.isCompleted) {
        checked.complete();
      }
    };
    final clock = Stopwatch()..start();
    sync.resume();
    await checked.future.timeout(const Duration(seconds: 15));
    clock.stop();
    // A new channel is joined despite the old leave still pending.
    final rejoined = Stopwatch()..start();
    while (realtime.joins < 2 && rejoined.elapsed.inSeconds < 15) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(realtime.joins, 2);
    expect(realtime.leaves, greaterThanOrEqualTo(1));
    await sync.dispose();
    await client.dispose();
    await db.close();
    await realtime.close();
    return clock.elapsed;
  }

  test(
    'resume checks the server without waiting for the old channel to leave',
    () async {
      final hung = await resumeLatency(answerLeave: false);
      final answered = await resumeLatency(answerLeave: true);
      // realtime_client waits up to 10 s for a leave acknowledgement; the
      // first server check must never queue behind it.
      expect(hung, lessThan(const Duration(seconds: 1)));
      expect(answered, lessThan(const Duration(seconds: 1)));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
