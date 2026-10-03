import 'package:deterministic_todo/data/editor_drafts.dart';
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_server.dart';

void main({bool includeDesktop = true}) {
  testWidgets(
    'sync icon immediately shows local pending work and opens details',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      final client = (await tester.runAsync(
        () => SyntheticSyncServer().client(),
      ))!;
      final sync = SyncService(db, client);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusAction(service: sync, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await repo.create('Stato sintetico');
      await tester.pumpAndSettle();
      expect(find.byTooltip('1 modifiche da sincronizzare'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Stato sintetico'), findsOneWidget);
      await db.delete(db.outboxEntries).go();
      await tester.pumpAndSettle();
      final task = await db.select(db.tasks).getSingle();
      await repo.updateDetails(task, title: task.title, notes: 'Solo la nota');
      await tester.pumpAndSettle();
      expect(find.text('Stato sintetico'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await sync.dispose();
        await client.dispose();
      });
      await db.close();
    },
  );

  for (final width in [400.0, if (includeDesktop) 1200.0]) {
    testWidgets(
      'upcoming resets on navigation and preserves scroll on task return at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final repo = TaskRepository(db, deviceId: 'fixture');
        await repo.create(
          'Domani sintetico',
          status: TaskStatus.scheduled,
          showDate: CivilDate.fromDateTime(
            DateTime.now(),
          ).addDays(1).toString(),
        );
        await tester.pumpWidget(
          TodoApp(repository: repo, enablePlatformServices: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prossime'));
        await tester.pumpAndSettle();
        final list = find.byWidgetPredicate(
          (w) => w is ListView && w.key.toString().contains('upcoming-'),
        );
        await tester.drag(list, const Offset(0, -1200));
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        expect(scroll.position.pixels, greaterThan(0));
        await tester.tap(find.text('Oggi'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prossime'));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(
                find
                    .descendant(of: list, matching: find.byType(Scrollable))
                    .first,
              )
              .position
              .pixels,
          0,
        );
        await tester.drag(list, const Offset(0, -30));
        await tester.pumpAndSettle();
        final beforeEditor = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position
            .pixels;
        await tester.tap(find.text('Domani sintetico'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.text('Domani sintetico'), findsOneWidget);
        expect(
          tester
              .state<ScrollableState>(
                find
                    .descendant(of: list, matching: find.byType(Scrollable))
                    .first,
              )
              .position
              .pixels,
          beforeEditor,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
      },
    );
  }

  testWidgets(
    'desktop closes after save and restores draft without reverting a remote field',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      final id = await repo.create('Titolo iniziale', notes: 'Nota iniziale');
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Titolo iniziale'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-editor-description')),
        'Bozza nota',
      );
      await tester.tap(find.byTooltip('Chiudi dettagli'));
      await tester.pumpAndSettle();
      expect(await EditorDrafts(db).read(id), isNotNull);
      final original = await db.select(db.tasks).getSingle();
      await db.withRevisionSource(
        'sync_pull',
        () => db
            .into(db.tasks)
            .insertOnConflictUpdate(
              original.copyWith(title: 'Titolo remoto', logicalVersion: 80),
            ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Titolo remoto'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task-editor-description')),
            )
            .controller!
            .text,
        'Bozza nota',
      );
      await tester.tap(find.byKey(const ValueKey('task-editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('Dettagli'), findsNothing);
      expect((await db.select(db.tasks).getSingle()).title, 'Titolo remoto');
      expect((await db.select(db.tasks).getSingle()).notes, 'Bozza nota');
      expect(await EditorDrafts(db).read(id), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
    skip: !includeDesktop,
  );

  testWidgets(
    'link can be added without selection and description is immediately visible',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      await repo.create('Link sintetico');
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link sintetico'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('task-editor-description')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Aggiungi link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('link-url')),
        'https://example.com/documento',
      );
      await tester.tap(find.text('Collega'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-editor-save')));
      await tester.pumpAndSettle();
      expect(
        (await db.select(db.tasks).getSingle()).notes,
        contains('https://example.com/documento'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  testWidgets(
    'quick composer draft survives dismissal and duplicate submission creates once',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nuova attività'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mobile-quick-add-field')),
        'Bozza nuova',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // The modal can also be dismissed through the platform back action.
      if (find
          .byKey(const ValueKey('mobile-quick-add-field'))
          .evaluate()
          .isNotEmpty) {
        Navigator.of(
          tester.element(find.byKey(const ValueKey('mobile-quick-add-field'))),
        ).pop();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Nuova attività'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile-quick-add-field')),
            )
            .controller!
            .text,
        'Bozza nuova',
      );
      await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
      await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
      await tester.pumpAndSettle();
      expect(await db.select(db.tasks).get(), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
  );
}
