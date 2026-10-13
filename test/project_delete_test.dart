import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Elimina» on a project with open tasks used to archive it and leave the
/// tasks bound to it, invisible in every project view (build 265).
void main() {
  Future<(AppDatabase, TaskRepository)> setUpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    return (db, TaskRepository(db, deviceId: 'synthetic'));
  }

  Future<void> close(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  }

  Future<Task> row(AppDatabase db, String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();

  testWidgets('deleting a project with open tasks moves them to Inbox', (
    tester,
  ) async {
    final (db, repository) = await setUpApp(tester);
    final project = await repository.createProject('Progetto sintetico');
    final task = await repository.create(
      'Attività sintetica',
      projectId: project,
      showDate: '2026-10-20',
    );
    await tester.pumpWidget(
      TodoApp(repository: repository, enablePlatformServices: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progetti'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('project-row-$project')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 attività aperta'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-project-with-tasks')),
    );
    await tester.pumpAndSettle();
    expect((await row(db, task)).projectId, isNull);
    expect((await row(db, task)).deletedAt, isNull);
    final archived = await (db.select(
      db.projects,
    )..where((p) => p.id.equals(project))).getSingle();
    expect(archived.isArchived, isTrue);
    await close(tester, db);
  });

  testWidgets('tasks left in an already deleted project can go to Inbox', (
    tester,
  ) async {
    final (db, repository) = await setUpApp(tester);
    final project = await repository.createProject('Collaudo sintetico');
    final open = await repository.create(
      'Aperta sintetica',
      projectId: project,
      showDate: '2026-10-20',
    );
    // State produced by builds up to 265: archived with tasks inside.
    await (db.update(db.projects)..where((p) => p.id.equals(project))).write(
      const ProjectsCompanion(isArchived: Value(true)),
    );
    expect(await repository.openTaskCount(project), 1);
    await tester.pumpWidget(
      TodoApp(repository: repository, enablePlatformServices: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progetti'));
    await tester.pumpAndSettle();
    expect(find.text('“Collaudo sintetico” è stato eliminato'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('orphaned-to-inbox-$project')));
    await tester.pumpAndSettle();
    expect((await row(db, open)).projectId, isNull);
    expect(find.text('“Collaudo sintetico” è stato eliminato'), findsNothing);
    final still = await (db.select(
      db.projects,
    )..where((p) => p.id.equals(project))).getSingle();
    expect(still.isArchived, isTrue);
    await close(tester, db);
  });
}
