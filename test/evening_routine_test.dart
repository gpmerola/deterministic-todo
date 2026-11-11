import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/evening_routine.dart';
import 'package:deterministic_todo/services/export_service.dart';
import 'package:deterministic_todo/ui/evening_routine_toggle.dart';
import 'package:deterministic_todo/ui/views/today_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flag survives reopen, new recurrence and backup restore', () async {
    final directory = await Directory.systemTemp.createTemp('evening-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = TaskRepository(db, deviceId: 'test');
    await repo.create('Synthetic evening', showDate: '2026-11-11');
    var task = await db.select(db.tasks).getSingle();
    await EveningRoutine(db).setEnabled(task, true);
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = TaskRepository(db, deviceId: 'test');
    expect(await EveningRoutine(db).watch().first, {task.id});
    await repo.updateDetails(
      task,
      title: task.title,
      showDate: task.showDate,
      recurrence: everyDayRecurrence,
    );
    task = await db.select(db.tasks).getSingle();
    expect(await EveningRoutine(db).watch().first, {task.seriesId});
    await repo.generateCalendarOccurrences(task, const CivilDate(2026, 11, 12));
    final next = (await db.select(db.tasks).get()).last;
    expect(EveningRoutine.identity(next), task.seriesId);
    final backup = await ExportService(db).exportJson();
    await db.close();
    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    await ExportService(restored).importValidated(backup);
    expect(await EveningRoutine(restored).watch().first, {task.seriesId});
    final outboxCount =
        (await restored.select(restored.outboxEntries).get()).length;
    await EveningRoutine(restored).setEnabled(next, false);
    expect(await EveningRoutine(restored).watch().first, isEmpty);
    expect(
      (await restored.select(restored.outboxEntries).get()).length,
      outboxCount,
    );
  });

  testWidgets(
    'manual checkbox groups only flagged tasks; can undo and reopen',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'test');
      await repo.create(
        'Morning',
        showDate: '2026-11-11',
        recurrence: everyDayRecurrence,
      );
      await repo.create(
        'Evening',
        showDate: '2026-11-11',
        recurrence: everyDayRecurrence,
      );
      final tasks = await db.select(db.tasks).get();
      final evening = tasks.firstWhere((task) => task.title == 'Evening');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EveningRoutineToggle(db: db, task: evening),
                Expanded(
                  child: TodayTaskList(
                    database: db,
                    tasks: tasks,
                    today: '2026-11-11',
                    tileBuilder: (task) => Text(task.title),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-evening-routine')));
      await tester.pumpAndSettle();
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Evening'), findsNothing);
      expect(find.text('1 attività'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('task-evening-routine')));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    },
  );
}
