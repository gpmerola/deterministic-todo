import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'riporta solo quotidiane aperte: identità, storico e retry preservati',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TaskRepository(db, deviceId: 'fixture');
      final eligible = await repo.create(
        'Sintetica daily',
        showDate: '2026-09-01',
        recurrence: everyDayRecurrence,
      );
      for (final rule in [
        null,
        'calendar:day:2',
        'calendar:weekday:1',
        'calendar:week:1',
        'afterCompletion:day:1',
      ]) {
        await repo.create(
          'Sintetica altra',
          showDate: '2026-09-01',
          recurrence: rule,
        );
      }
      for (final date in [null, '2026-09-27', '2026-09-28']) {
        await repo.create(
          'Sintetica data',
          showDate: date,
          recurrence: everyDayRecurrence,
        );
      }
      for (final status in [TaskStatus.waiting, TaskStatus.completed]) {
        await repo.create(
          'Sintetica stato',
          showDate: '2026-09-01',
          recurrence: everyDayRecurrence,
          status: status,
        );
      }
      final deletedId = await repo.create(
        'Sintetica eliminata',
        showDate: '2026-09-01',
        recurrence: everyDayRecurrence,
      );
      final deleted = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(deletedId))).getSingle();
      await repo.softDelete(deleted);
      final before = {for (final t in await db.select(db.tasks).get()) t.id: t};
      await db.delete(db.outboxEntries).go();
      expect(await repo.maintainDailyTasks('2026-09-27').first, 1);
      final after = await db.select(db.tasks).get();
      expect(after.length, before.length);
      for (final task in after) {
        final old = before[task.id]!;
        if (task.id != eligible) {
          expect(task, old);
        } else {
          expect(task.showDate, '2026-09-27');
          expect(task.completedAt, isNull);
          expect(task.seriesId, old.seriesId);
          expect(task.occurrenceKey, old.occurrenceKey);
          expect(task.position, old.position);
          expect(task.logicalVersion, old.logicalVersion + 1);
        }
      }
      expect(await repo.maintainDailyTasks('2026-09-27').first, 0);
      expect((await db.select(db.outboxEntries).get()).length, 1);
      // Completion after rollover generates tomorrow, not a second task today.
      final task = after.singleWhere((t) => t.id == eligible);
      final currentDay = CivilDate.fromDateTime(DateTime.now());
      await repo.maintainDailyTasks(currentDay.toString()).first;
      final updated = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(task.id))).getSingle();
      expect(await repo.setCompleted(updated, true), currentDay.addDays(1));
    },
  );

  test('lo stream gestisce arrivi tardivi senza polling', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db, deviceId: 'fixture');
    final events = <int>[];
    final subscription = repo
        .maintainDailyTasks('2026-09-27')
        .listen(events.add);
    await pumpEventQueue();
    expect(events, contains(0));
    await repo.create(
      'Sintetica importata',
      showDate: '2026-09-01',
      recurrence: everyDayRecurrence,
    );
    await pumpEventQueue();
    expect((await db.select(db.tasks).getSingle()).showDate, '2026-09-27');
    expect(events.where((n) => n > 0), [1]);
    await subscription.cancel();
    await db.close();
  });
}
