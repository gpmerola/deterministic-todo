import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/services/auto_backup_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measures the real Dart preparation path, before Android encryption/IO.
/// Explicit opt-in: timing/RSS vary by host and must not gate CI.
void main() {
  for (final count in [100, 1000, 10000]) {
    test(
      'backup preparation benchmark: $count synthetic rows',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.batch(
          (batch) => batch.insertAll(db.tasks, [
            for (var i = 0; i < count; i++)
              TasksCompanion.insert(
                id: 'benchmark-$i',
                title: 'Synthetic backup $i',
                notes: Value('x' * 1000),
                status: 'scheduled',
                position: i,
                createdAt: i,
                updatedAt: i,
                deviceId: 'synthetic-benchmark',
              ),
          ]),
        );
        final store = _CaptureStore();
        final service = AutoBackupService(db, store: store);
        for (var sample = 0; sample < 3; sample++) {
          store.bytes = null;
          final rssBefore = ProcessInfo.currentRss;
          final elapsed = Stopwatch()..start();
          var lastTick = 0, maxGapUs = 0;
          void tick() {
            final now = elapsed.elapsedMicroseconds;
            final gap = now - lastTick;
            if (gap > maxGapUs) maxGapUs = gap;
            lastTick = now;
          }

          final probe = Timer.periodic(
            const Duration(milliseconds: 1),
            (_) => tick(),
          );
          try {
            expect(
              await service.backupNow(now: DateTime.utc(2026, 10, 13)),
              isTrue,
            );
            tick();
          } finally {
            probe.cancel();
            elapsed.stop();
          }
          final rssAfter = ProcessInfo.currentRss;
          final bytes = store.bytes!;
          final decoded = jsonDecode(utf8.decode(bytes)) as Map;
          expect(decoded['version'], 2);
          expect(decoded['tasks'], hasLength(count));
          // No titles, notes, credentials or real data in measurement output.
          // ignore: avoid_print
          print(
            jsonEncode({
              'benchmark': 'backup_preparation',
              'rows': count,
              'note_bytes_per_row': 1000,
              'sample': sample,
              'duration_us': elapsed.elapsedMicroseconds,
              'max_event_loop_gap_us': maxGapUs,
              'payload_bytes': bytes.length,
              'rss_before': rssBefore,
              'rss_after': rssAfter,
            }),
          );
        }
      },
      skip: !const bool.fromEnvironment('RUN_BACKUP_BENCHMARK'),
    );
  }
}

class _CaptureStore implements EncryptedBackupStore {
  Uint8List? bytes;
  @override
  Future<bool> configured() async => true;
  @override
  Future<List<AutoBackupEntry>> list() async => []; // Force every measured write.
  @override
  Future<void> write(
    String name,
    Uint8List content, {
    required int keep,
  }) async {
    bytes = content;
  }

  @override
  Future<String> setup() => throw UnimplementedError();
  @override
  Future<Uint8List> read(String name) => throw UnimplementedError();
  @override
  Future<Uint8List> decrypt(Uint8List content, {String? code}) =>
      throw UnimplementedError();
}
