import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  for (final phoneRolledOver in [false, true]) {
    test('a stale device moving a daily task never reopens a completion '
        '(phone rolled over: $phoneRolledOver)', () async {
      final today = CivilDate.fromDateTime(DateTime.now());
      final yesterday = today.addDays(-1).toString();
      final server = SyntheticSyncServer()
        ..overview = true
        ..contentFingerprints = true;
      final phoneDb = AppDatabase.forTesting(NativeDatabase.memory());
      final webDb = AppDatabase.forTesting(NativeDatabase.memory());
      final phone = TaskRepository(phoneDb, deviceId: 'phone');
      final web = TaskRepository(webDb, deviceId: 'web');
      final phoneClient = await server.client();
      final webClient = await server.client();
      final phoneSync = SyncService(phoneDb, phoneClient);
      final webSync = SyncService(webDb, webClient);

      // Yesterday's occurrence, still in the state given at creation.
      final id = await phone.create(
        'Sintetica quotidiana',
        showDate: yesterday,
        recurrence: everyDayRecurrence,
        status: TaskStatus.scheduled,
      );
      await phoneSync.sync();
      await webSync.sync(); // The Web tab keeps this copy overnight.

      if (phoneRolledOver) {
        await phone.maintainDailyTasks(today.toString()).first;
      }
      final current = await (phoneDb.select(
        phoneDb.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      await phone.setCompleted(current, true);
      await phoneSync.sync();

      // The Web tab resumes: its day rolls over before it has pulled.
      await web.maintainDailyTasks(today.toString()).first;
      await webSync.sync();
      await phoneSync.sync();

      for (final db in [phoneDb, webDb]) {
        final row = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.status, TaskStatus.completed.name);
        expect(row.completedAt, isNotNull);
      }
      expect(server.tables['tasks']![id]!['status'], 'completed');
      for (final db in [phoneDb, webDb]) {
        expect(await db.select(db.outboxEntries).get(), isEmpty);
      }
      await phoneSync.dispose();
      await webSync.dispose();
      await phoneClient.dispose();
      await webClient.dispose();
      await phoneDb.close();
      await webDb.close();
    });
  }

  test(
    'the guarded move still reaches the server when nothing changed',
    () async {
      final today = CivilDate.fromDateTime(DateTime.now());
      final server = SyntheticSyncServer()
        ..overview = true
        ..contentFingerprints = true;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'web');
      final client = await server.client();
      final sync = SyncService(db, client);
      final id = await repo.create(
        'Sintetica quotidiana',
        showDate: today.addDays(-2).toString(),
        recurrence: everyDayRecurrence,
        status: TaskStatus.scheduled,
      );
      await sync.sync();
      expect(await repo.maintainDailyTasks(today.toString()).first, 1);
      await sync.sync();
      final remote = server.tables['tasks']![id]!;
      expect(remote['show_date'], today.toString());
      expect(remote['status'], TaskStatus.available.name);
      expect(await db.select(db.outboxEntries).get(), isEmpty);
      await sync.dispose();
      await client.dispose();
      await db.close();
    },
  );
}
