import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main({bool resize = true}) {
  for (final systemBack in [false, true]) {
    testWidgets('project reopens after scrolling, system back=$systemBack', (
      tester,
    ) async {
      if (resize) {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TaskRepository(db, deviceId: 'synthetic');
      final project = await repository.createProject('Progetto di prova');
      final section = await repository.createProjectSection(
        project,
        'Sezione di prova',
      );
      for (var i = 0; i < 20; i++) {
        await repository.create(
          'Attività sintetica $i',
          projectId: project,
          sectionId: section,
        );
      }
      await tester.pumpWidget(
        TodoApp(repository: repository, enablePlatformServices: false),
      );
      await tester.pump();
      await tester.tap(find.text('Progetti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progetto di prova'));
      await tester.pumpAndSettle();
      final list = find.byKey(PageStorageKey('project-list-$project'));
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      expect(before, greaterThan(0));
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byKey(const ValueKey('back-to-projects')));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progetto di prova'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      final after = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      expect(after, closeTo(before, 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });
  }

  testWidgets(
    'sections and unsectioned group keep independent state across projects',
    (tester) async {
      if (resize) {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'synthetic');
      final first = await repo.createProject('Primo progetto');
      final second = await repo.createProject('Secondo progetto');
      final a = await repo.createProjectSection(first, 'Sezione A');
      final b = await repo.createProjectSection(first, 'Sezione B');
      final other = await repo.createProjectSection(second, 'Sezione A');
      await repo.create('Attività A', projectId: first, sectionId: a);
      await repo.create('Attività B', projectId: first, sectionId: b);
      await repo.create('Attività libera', projectId: first);
      await repo.create('Altra attività', projectId: second, sectionId: other);
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pump();
      await tester.tap(find.text('Progetti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Primo progetto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sezione A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senza sezione'));
      await tester.pumpAndSettle();
      expect(find.text('Attività A'), findsNothing);
      expect(find.text('Attività libera'), findsNothing);
      expect(find.text('Attività B'), findsOneWidget);
      Future<void> back() async {
        await tester.tap(find.byKey(const ValueKey('back-to-projects')));
        await tester.pumpAndSettle();
      }

      await back();
      await tester.tap(find.text('Secondo progetto'));
      await tester.pumpAndSettle();
      expect(find.text('Altra attività'), findsOneWidget);
      await back();
      await tester.tap(find.text('Primo progetto'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Attività A'), findsNothing);
      expect(find.text('Attività libera'), findsNothing);
      expect(find.text('Attività B'), findsOneWidget);
      await tester.tap(find.text('Sezione A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senza sezione'));
      await tester.pumpAndSettle();
      expect(find.text('Attività A'), findsOneWidget);
      expect(find.text('Attività libera'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
  );
}
