import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/conflict_resolver.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('Android e Web convergono dopo modifiche offline concorrenti', () async {
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

    var androidOccurrence = await (androidDb.select(
      androidDb.tasks,
    )..where((row) => row.showDate.equals('2026-08-09'))).getSingle();
    var webOccurrence = await (webDb.select(
      webDb.tasks,
    )..where((row) => row.showDate.equals('2026-08-09'))).getSingle();
    expect(androidOccurrence.id, webOccurrence.id);

    await android.updateDetails(
      androidOccurrence,
      title: 'Modifica Android',
      showDate: androidOccurrence.showDate,
      recurrence: androidOccurrence.recurrence,
    );
    await web.updateDetails(
      webOccurrence,
      title: 'Modifica Web',
      showDate: webOccurrence.showDate,
      recurrence: webOccurrence.recurrence,
    );
    androidOccurrence = await (androidDb.select(
      androidDb.tasks,
    )..where((row) => row.id.equals(androidOccurrence.id))).getSingle();
    webOccurrence = await (webDb.select(
      webDb.tasks,
    )..where((row) => row.id.equals(webOccurrence.id))).getSingle();

    final winnerOnAndroid = resolveConflict(
      local: androidOccurrence,
      localVersion: LogicalVersion(
        androidOccurrence.logicalVersion,
        androidOccurrence.deviceId,
      ),
      remote: webOccurrence,
      remoteVersion: LogicalVersion(
        webOccurrence.logicalVersion,
        webOccurrence.deviceId,
      ),
    );
    final winnerOnWeb = resolveConflict(
      local: webOccurrence,
      localVersion: LogicalVersion(
        webOccurrence.logicalVersion,
        webOccurrence.deviceId,
      ),
      remote: androidOccurrence,
      remoteVersion: LogicalVersion(
        androidOccurrence.logicalVersion,
        androidOccurrence.deviceId,
      ),
    );

    expect(winnerOnAndroid.id, winnerOnWeb.id);
    expect(winnerOnAndroid.title, winnerOnWeb.title);
    expect(winnerOnAndroid.logicalVersion, winnerOnWeb.logicalVersion);
    expect(winnerOnAndroid.deviceId, winnerOnWeb.deviceId);
  });
}
