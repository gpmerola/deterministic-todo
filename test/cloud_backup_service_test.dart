import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/cloud_backup_service.dart';
import 'package:deterministic_todo/services/export_service.dart';
import 'package:deterministic_todo/ui/cloud_backup_sheet.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// In-memory stand-in for the table and RPC; the SQL itself is covered by
/// tools/sql-tests/todo_cloud_backups.mjs (pruning, RLS, validation).
class _FakeRemote implements CloudBackupRemote {
  bool signedIn = true;
  bool fail = false;
  int saves = 0, hashReads = 0;
  final rows = <({CloudBackupEntry entry, String hash, String content})>[];

  @override
  bool get available => signedIn;

  void _check() {
    if (fail) throw StateError('synthetic offline');
  }

  @override
  Future<String?> latestHash() async {
    _check();
    hashReads++;
    return rows.isEmpty ? null : rows.first.hash;
  }

  @override
  Future<String> save({
    required String content,
    required String hash,
    required int size,
    required String deviceId,
  }) async {
    _check();
    saves++;
    if (rows.isNotEmpty && rows.first.hash == hash) return 'unchanged';
    rows.insert(0, (
      entry: CloudBackupEntry(
        id: 'copy-$saves',
        savedAt: DateTime.utc(2026, 11, 19, 12, saves),
        sizeBytes: size,
        deviceId: deviceId,
      ),
      hash: hash,
      content: content,
    ));
    if (rows.length > CloudBackupService.keep) rows.removeLast();
    return 'saved';
  }

  @override
  Future<List<CloudBackupEntry>> list() async {
    _check();
    return [for (final r in rows) r.entry];
  }

  @override
  Future<String> content(String id) async {
    _check();
    return rows.firstWhere((r) => r.entry.id == id).content;
  }
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it');
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late TaskRepository repository;
  late _FakeRemote remote;
  late DateTime now;
  late CloudBackupService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(db, deviceId: 'device-a');
    remote = _FakeRemote();
    now = DateTime.utc(2026, 11, 19, 9);
    service = CloudBackupService(
      db,
      remote,
      deviceId: 'device-a',
      now: () => now,
    );
  });
  tearDown(() => db.close());

  Future<String?> setting(String key) async => (await (db.select(
    db.appSettings,
  )..where((r) => r.key.equals(key))).getSingleOrNull())?.value;

  test('one copy a day, uploaded only when the content changed', () async {
    await repository.create('Synthetic one');
    expect(await service.runIfDue(), isTrue);
    expect(remote.saves, 1);
    expect(remote.rows.single.entry.deviceId, 'device-a');

    // Same day: nothing at all, not even a read.
    now = now.add(const Duration(hours: 5));
    expect(await service.runIfDue(), isFalse);
    expect(remote.hashReads, 1);

    // Next day, unchanged: one small read, no upload.
    now = now.add(const Duration(days: 1));
    expect(await service.runIfDue(), isFalse);
    expect(remote.hashReads, 2);
    expect(remote.saves, 1);
    expect(await setting(CloudBackupService.lastAtKey), now.toIso8601String());

    // Next day, changed: a second copy.
    await repository.create('Synthetic two');
    now = now.add(const Duration(days: 1));
    expect(await service.runIfDue(), isTrue);
    expect(remote.rows, hasLength(2));
  });

  test('without an account nothing is attempted or recorded', () async {
    remote.signedIn = false;
    expect(await service.runIfDue(), isFalse);
    expect(remote.hashReads, 0);
    expect(await setting(CloudBackupService.attemptAtKey), isNull);
  });

  test('a failure is recorded, retried after hours, then cleared', () async {
    remote.fail = true;
    expect(await service.runIfDue(), isFalse);
    var status = await service.status();
    expect(status.lastAttemptFailed, isTrue);
    expect(status.entries, isNull);

    remote.fail = false;
    now = now.add(const Duration(hours: 1));
    expect(await service.runIfDue(), isFalse, reason: 'waits for the retry');
    expect(remote.hashReads, 0);

    now = now.add(CloudBackupService.retry);
    expect(await service.runIfDue(), isTrue);
    status = await service.status();
    expect(status.lastAttemptFailed, isFalse);
    expect(status.latest!.id, 'copy-1');
    await expectLater(service.backupNow(), completion(isFalse));
    remote.fail = true;
    await expectLater(service.backupNow(), throwsStateError);
  });

  test('a copy restores on another device through the import preview, '
      'byte for byte equal to the local export', () async {
    await repository.create('Synthetic restore');
    await service.backupNow();
    final stored = remote.rows.single;
    // gzip + base64: much smaller than the JSON it carries.
    expect(stored.content.length, lessThan(stored.entry.sizeBytes));

    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    final restoring = CloudBackupService(
      other,
      remote,
      deviceId: 'device-b',
      now: () => now,
    );
    final source = await restoring.read(stored.entry);
    final local = await ExportService(db).exportBackup();
    expect(backupContentHash(source), local.contentHash);
    expect(utf8.encode(source).length, stored.entry.sizeBytes);

    final importer = ExportService(other);
    final preview = await importer.preview(source);
    expect(preview.added, 1);
    // Nothing changes before the explicit import.
    expect(await other.select(other.tasks).get(), isEmpty);
    await importer.importValidated(source);
    expect(
      (await other.select(other.tasks).getSingle()).title,
      'Synthetic restore',
    );
  });

  testWidgets('the sheet shows the newest copy and returns it to restore', (
    tester,
  ) async {
    late CloudBackupEntry newest;
    await tester.runAsync(() async {
      await repository.create('Synthetic sheet');
      await service.backupNow();
      await repository.create('Synthetic sheet two');
      await service.backupNow();
      newest = remote.rows.first.entry;
    });
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showModalBottomSheet(
              context: context,
              builder: (_) =>
                  CloudBackupSheet(backups: service, deviceId: 'device-a'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-backup-latest')), findsOneWidget);
    expect(find.textContaining('da questo dispositivo'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('cloud-backup-restore-latest')));
    await tester.pumpAndSettle();
    expect(identical(result, newest), isTrue);
  });

  testWidgets('an unreachable server is said plainly', (tester) async {
    remote.fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudBackupSheet(backups: service, deviceId: 'device-a'),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cloud-backup-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cloud-backup-restore-latest')),
      findsNothing,
    );
  });
}
