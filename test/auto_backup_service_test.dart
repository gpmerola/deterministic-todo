import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/auto_backup_service.dart';
import 'package:deterministic_todo/services/export_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the Android channel (encryption is tested on the
/// JVM in TodoBackupTest). Models rotation, the key and a wrong code.
class _FakeStore implements EncryptedBackupStore {
  bool isConfigured = false;
  bool failWrites = false;
  int writes = 0;
  final files = <String, Uint8List>{};

  @override
  Future<bool> configured() async => isConfigured;

  @override
  Future<String> setup() async {
    isConfigured = true;
    return 'SYNTHETIC-CODE';
  }

  @override
  Future<void> write(
    String name,
    Uint8List content, {
    required int keep,
  }) async {
    if (!isConfigured) throw PlatformException(code: 'not_configured');
    if (failWrites) throw PlatformException(code: 'backup_failed');
    writes++;
    files[name] = content;
    final names = files.keys.toList()..sort();
    for (final old in names.take(
      names.length > keep ? names.length - keep : 0,
    )) {
      files.remove(old);
    }
  }

  @override
  Future<List<AutoBackupEntry>> list() async => [
    for (final e in files.entries) AutoBackupEntry(e.key, e.value.length),
  ];

  @override
  Future<Uint8List> read(String name) async => files[name]!;

  @override
  Future<Uint8List> decrypt(Uint8List content, {String? code}) async {
    if (code != null && code != 'SYNTHETIC-CODE') {
      throw PlatformException(code: 'key_mismatch');
    }
    return content;
  }
}

void main() {
  late AppDatabase db;
  late TaskRepository repo;
  late _FakeStore store;
  var now = DateTime.utc(2026, 10, 12, 9);
  AutoBackupService service() =>
      AutoBackupService(db, store: store, now: () => now);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db, deviceId: 'synthetic-device');
    store = _FakeStore();
    now = DateTime.utc(2026, 10, 12, 9);
    await repo.create('Synthetic backup task');
  });
  tearDown(() => db.close());

  test('nothing runs until the user activates backups', () async {
    expect(await service().runIfDue(), isFalse);
    expect(store.writes, 0);
    final attempt =
        await (db.select(db.appSettings)
              ..where((r) => r.key.equals(AutoBackupService.attemptAtKey)))
            .getSingleOrNull();
    expect(attempt, isNull);
  });

  test('activation returns the code and writes the first backup', () async {
    expect(await service().activate(), 'SYNTHETIC-CODE');
    expect(store.files.keys, ['todo-20261012T090000Z.tdb']);
  });

  test('weekly cadence, unchanged content is not rewritten', () async {
    store.isConfigured = true;
    expect(await service().runIfDue(), isTrue);
    now = now.add(const Duration(days: 6, hours: 23));
    expect(await service().runIfDue(), isFalse);
    expect(store.writes, 1);
    // Due again, but only `exported_at` would differ: no new file.
    now = now.add(const Duration(hours: 2));
    expect(await service().runIfDue(), isFalse);
    expect(store.writes, 1);
    // The check itself counts: the next one is a week later.
    now = now.add(const Duration(days: 1));
    await repo.create('Synthetic change');
    expect(await service().runIfDue(), isFalse);
    now = now.add(const Duration(days: 7));
    expect(await service().runIfDue(), isTrue);
    expect(store.files, hasLength(2));
  });

  test('history keeps the newest six files', () async {
    store.isConfigured = true;
    for (var week = 0; week < 8; week++) {
      await repo.create('Synthetic week $week');
      await service().backupNow(now: now.add(Duration(days: 7 * week)));
    }
    final names = store.files.keys.toList()..sort();
    expect(names, hasLength(AutoBackupService.keep));
    expect(names.first, 'todo-20261026T090000Z.tdb');
  });

  test('a failure is retried at most once a day and never throws', () async {
    store
      ..isConfigured = true
      ..failWrites = true;
    expect(await service().runIfDue(), isFalse);
    store.failWrites = false;
    now = now.add(const Duration(hours: 23));
    expect(await service().runIfDue(), isFalse);
    expect(store.writes, 0);
    now = now.add(const Duration(hours: 2));
    expect(await service().runIfDue(), isTrue);
  });

  test('concurrent triggers (start and resume) write once', () async {
    store.isConfigured = true;
    final backups = service();
    final results = await Future.wait([backups.runIfDue(), backups.runIfDue()]);
    expect(results, [true, true]);
    expect(store.writes, 1);
  });

  test(
    'a backup restores into an empty database through the preview',
    () async {
      store.isConfigured = true;
      final backups = service();
      await backups.backupNow();
      final entry = (await backups.list()).single;
      final source = await backups.read(entry);
      expect((jsonDecode(source) as Map)['format'], 'deterministic_todo');

      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      final export = ExportService(fresh);
      expect((await export.preview(source)).added, 1);
      await export.importValidated(source);
      expect(
        (await fresh.select(fresh.tasks).getSingle()).title,
        'Synthetic backup task',
      );
      await fresh.close();

      final picked = Uint8List.fromList(utf8.encode(source));
      expect(await backups.decryptFile(picked, code: 'SYNTHETIC-CODE'), source);
      await expectLater(
        backups.decryptFile(picked, code: 'WRONG'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('file names sort chronologically and parse back', () {
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final name = AutoBackupService.fileName(at);
    expect(name, 'todo-20260102T030405Z.tdb');
    expect(AutoBackupEntry(name, 1).savedAt, at);
  });
}
