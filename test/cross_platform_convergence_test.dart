import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test(
    'Android e Web generano le stesse occorrenze con lo stesso ID',
    () async {
      final androidDb = AppDatabase.forTesting(NativeDatabase.memory());
      final webDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(androidDb.close);
      addTearDown(webDb.close);
      final android = TaskRepository(
        androidDb,
        deviceId: '00000000-0000-4000-8000-000000000001',
      );
      final web = TaskRepository(
        webDb,
        deviceId: '00000000-0000-4000-8000-000000000002',
      );
      const seriesId = '00000000-0000-4000-8000-000000000100';
      const rule = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      );

      for (final db in [androidDb, webDb]) {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: seriesId,
                title: 'Controllo giornaliero',
                status: TaskStatus.available.name,
                showDate: const Value('2026-08-08'),
                recurrence: Value(rule.encode()),
                seriesId: const Value(seriesId),
                occurrenceKey: const Value('2026-08-08'),
                position: 1024,
                createdAt: 1,
                updatedAt: 1,
                deviceId: '00000000-0000-4000-8000-000000000000',
              ),
            );
      }

      final androidSource = await androidDb.select(androidDb.tasks).getSingle();
      final webSource = await webDb.select(webDb.tasks).getSingle();
      await android.generateCalendarOccurrences(
        androidSource,
        const CivilDate(2026, 8, 9),
      );
      await web.generateCalendarOccurrences(
        webSource,
        const CivilDate(2026, 8, 9),
      );

      final androidOccurrence = await (androidDb.select(
        androidDb.tasks,
      )..where((row) => row.showDate.equals('2026-08-09'))).getSingle();
      final webOccurrence = await (webDb.select(
        webDb.tasks,
      )..where((row) => row.showDate.equals('2026-08-09'))).getSingle();
      expect(androidOccurrence.id, webOccurrence.id);
    },
  );

  test('Android e Web convergono dopo modifiche offline concorrenti', () async {
    // The app's real path: local edits with Lamport versions, then sync
    // through a synthetic PostgREST server with CAS, in any order.
    final server = SyntheticSyncServer();
    final androidDb = AppDatabase.forTesting(NativeDatabase.memory());
    final webDb = AppDatabase.forTesting(NativeDatabase.memory());
    final android = TaskRepository(
      androidDb,
      deviceId: '00000000-0000-4000-8000-000000000001',
    );
    final web = TaskRepository(
      webDb,
      deviceId: '00000000-0000-4000-8000-000000000002',
    );
    final androidClient = await server.client();
    final webClient = await server.client();
    final androidSync = SyncService(androidDb, androidClient);
    final webSync = SyncService(webDb, webClient);
    addTearDown(() async {
      await androidSync.dispose();
      await webSync.dispose();
      await androidClient.dispose();
      await webClient.dispose();
      await androidDb.close();
      await webDb.close();
    });

    final id = await android.create('Originale sintetico');
    await androidSync.sync();
    await webSync.sync();
    Future<Task> row(AppDatabase db) =>
        (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();

    // Both edit offline, then sync: Android, Web, Android again.
    final onAndroid = await row(androidDb);
    await android.updateDetails(
      onAndroid,
      title: 'Modifica Android',
      showDate: onAndroid.showDate,
      recurrence: onAndroid.recurrence,
    );
    final onWeb = await row(webDb);
    await web.updateDetails(
      onWeb,
      title: 'Modifica Web',
      showDate: onWeb.showDate,
      recurrence: onWeb.recurrence,
    );
    await androidSync.sync();
    await webSync.sync();
    await androidSync.sync();

    final a = await row(androidDb);
    final w = await row(webDb);
    final remote = server.tables['tasks']![id]!;
    expect(a.title, w.title);
    expect(a.title, remote['title']);
    expect(a.logicalVersion, w.logicalVersion);
    expect(a.deviceId, w.deviceId);
    expect(['Modifica Android', 'Modifica Web'], contains(a.title));
    expect(await androidDb.select(androidDb.outboxEntries).get(), isEmpty);
    expect(await webDb.select(webDb.outboxEntries).get(), isEmpty);
  });
}
