import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data nulla e stato persistono riaprendo SQLite nativo', () async {
    final directory = await Directory.systemTemp.createTemp('todo-date-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fixture.sqlite');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = TaskRepository(db, deviceId: 'test-device');
    final projectId = await repository.createProject('Progetto sintetico');
    await repository.create(
      'Attività sintetica',
      projectId: projectId,
      showDate: '2026-09-06',
      status: TaskStatus.available,
    );
    final original = await db.select(db.tasks).getSingle();
    await repository.updateDetails(
      original,
      title: original.title,
      showDate: null,
      status: TaskStatus.inbox,
    );
    await db.close();

    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final saved = await reopened.select(reopened.tasks).getSingle();
      expect(saved.showDate, isNull);
      expect(saved.status, TaskStatus.inbox.name);
      expect(saved.projectId, projectId);
      expect(saved.logicalVersion, original.logicalVersion + 1);
      expect(await reopened.select(reopened.outboxEntries).get(), hasLength(2));
    } finally {
      await reopened.close();
    }
  });

  for (final width in [400.0, 1200.0]) {
    for (final useClose in [false, true]) {
      testWidgets(
        '${useClose ? 'X' : 'Senza data'} conserva il backlog del progetto a $width px',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          final repository = TaskRepository(db, deviceId: 'test-device');
          final projectId = await repository.createProject(
            'Progetto sintetico',
          );
          final sectionId = await repository.createProjectSection(
            projectId,
            'Sezione sintetica',
          );
          await repository.create(
            'Attività sintetica',
            status: useClose ? TaskStatus.scheduled : TaskStatus.available,
            showDate: CivilDate.fromDateTime(
              DateTime.now(),
            ).addDays(useClose ? 1 : 0).toString(),
            projectId: projectId,
            sectionId: sectionId,
            notes: 'Nota sintetica',
            priority: 3,
          );
          await tester.pumpWidget(TodoApp(repository: repository));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Progetti'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Progetto sintetico'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Attività sintetica'));
          await tester.pumpAndSettle();
          final noDate = find.byKey(const ValueKey('task-editor-no-date'));
          await tester.tap(useClose ? find.byTooltip('Rimuovi data') : noDate);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(noDate).selected, isTrue);
          await tester.tap(find.byKey(const ValueKey('task-editor-save')));
          await tester.pumpAndSettle();

          var saved = await db.select(db.tasks).getSingle();
          expect(saved.showDate, isNull);
          expect(saved.status, TaskStatus.inbox.name);
          expect(saved.projectId, projectId);
          expect(saved.sectionId, sectionId);
          expect(saved.notes, 'Nota sintetica');
          expect(saved.priority, 3);
          // Date, status and the outbox must advance as one saved version.
          expect(saved.logicalVersion, 2);
          expect(find.text('Attività sintetica'), findsOneWidget);

          // A later edit must preserve the persisted null, including in-place
          // desktop editors, and enqueue the saved version for synchronization.
          await tester.tap(find.text('Attività sintetica'));
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(noDate).selected, isTrue);
          await tester.enterText(
            find.byKey(const ValueKey('task-editor-title')),
            'Attività sintetica modificata',
          );
          await tester.tap(find.byKey(const ValueKey('task-editor-save')));
          await tester.pumpAndSettle();
          saved = await db.select(db.tasks).getSingle();
          expect(saved.showDate, isNull);
          expect(saved.status, TaskStatus.inbox.name);
          expect(saved.title, 'Attività sintetica modificata');
          expect(saved.logicalVersion, 3);
          final pending = await (db.select(
            db.outboxEntries,
          )..where((row) => row.entityId.equals(saved.id))).get();
          expect(pending, hasLength(3));
          expect(
            pending.any(
              (entry) =>
                  (jsonDecode(entry.payload)
                      as Map<String, dynamic>)['version'] ==
                  saved.logicalVersion,
            ),
            isTrue,
          );

          await tester.tap(find.text('Oggi').first);
          await tester.pumpAndSettle();
          expect(find.text('Attività sintetica modificata'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          await db.close();
        },
      );
    }
  }

  testWidgets('Senza data prevale sulla data nel titolo', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Attività sintetica');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attività sintetica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-editor-title')),
      'Attività sintetica domani',
    );
    await tester.tap(find.byKey(const ValueKey('task-editor-no-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-editor-save')));
    await tester.pumpAndSettle();
    final saved = await db.select(db.tasks).getSingle();
    expect(saved.showDate, isNull);
    expect(saved.status, TaskStatus.inbox.name);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
