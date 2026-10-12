import 'dart:async';

import 'package:deterministic_todo/data/editor_drafts.dart';
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/ui/priority_color.dart';
import 'package:deterministic_todo/ui/quick_add_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  for (final width in [400.0, 1200.0]) {
    testWidgets('preview matches stored metadata at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      final project = await repo.createProject('Progetto sintetico');
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nuova attività'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('mobile-quick-add-field'));
      final submit = find.byKey(const ValueKey('mobile-quick-add-submit'));
      expect(tester.widget<IconButton>(submit).onPressed, isNull);
      await tester.enterText(field, 'Leggi');
      await tester.pump();
      expect(
        find.textContaining(
          DateFormat('EEE d MMM yyyy', 'it').format(DateTime.now()),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nessun progetto · Nessuna priorità'),
        findsOneWidget,
      );
      await tester.enterText(field, 'Leggi #Progetto sintetico p1 ogni giorno');
      await tester.pump();
      expect(
        find.textContaining('Progetto sintetico · Priorità P1'),
        findsOneWidget,
      );
      expect(find.textContaining('ogni giorno'), findsWidgets);
      final priorityMenu = tester.widget<PopupMenuButton<int>>(
        find.byKey(const ValueKey('mobile-quick-add-priority')),
      );
      expect(priorityMenu.tooltip, 'Priorità P1');
      expect(priorityMenu.initialValue, 4);
      expect((priorityMenu.icon! as Icon).color, priorityColor(4));
      final projectMenu = tester.widget<PopupMenuButton<String>>(
        find.byKey(const ValueKey('mobile-quick-add-project')),
      );
      expect(projectMenu.tooltip, 'Progetto: Progetto sintetico');
      expect(projectMenu.initialValue, project);
      expect((projectMenu.icon! as Icon).icon, Icons.folder);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final task = await db.select(db.tasks).getSingle();
      expect(task.title, 'Leggi');
      expect(task.projectId, project);
      expect(task.priority, 4);
      expect(task.recurrence, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });
    testWidgets('menu selections update tokens and stored metadata at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'fixture');
      await repo.createProject('Progetto A');
      final second = await repo.createProject('Progetto B');
      await tester.pumpWidget(
        TodoApp(repository: repo, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nuova attività'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('mobile-quick-add-field'));
      final priorityMenu = find.byKey(
        const ValueKey('mobile-quick-add-priority'),
      );
      final projectMenu = find.byKey(
        const ValueKey('mobile-quick-add-project'),
      );
      await tester.enterText(field, 'Leggi #Progetto A p1 domani');
      await tester.pump();
      await tester.tap(priorityMenu);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CheckedPopupMenuItem<int>>(
              find.byType(CheckedPopupMenuItem<int>),
            )
            .singleWhere((item) => item.checked)
            .value,
        4,
      );
      await tester.tap(
        find.ancestor(
          of: find.text('P2'),
          matching: find.byType(CheckedPopupMenuItem<int>),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Leggi #Progetto A p2 domani',
      );
      expect(find.byTooltip('Priorità P2'), findsOneWidget);
      await tester.tap(projectMenu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Progetto B'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Progetto: Progetto B'), findsOneWidget);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Leggi #Progetto B p2 domani',
      );
      // Removing a token restores the explicit selection, not a stale icon.
      await tester.enterText(field, 'Leggi p1 domani');
      await tester.pump();
      expect(find.byTooltip('Progetto: Progetto B'), findsOneWidget);
      await tester.enterText(field, 'Leggi domani');
      await tester.pump();
      expect(find.byTooltip('Priorità P2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
      await tester.pumpAndSettle();
      final task = await db.select(db.tasks).getSingle();
      expect(task.title, 'Leggi');
      expect(task.priority, 3);
      expect(task.projectId, second);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });
  }

  testWidgets('invalid date stays editable and pending submit cannot repeat', (
    tester,
  ) async {
    await initializeDateFormatting('it');
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final result = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuickAddSheet(
                context,
                projects: [],
                draftStore: EditorDrafts(db),
                onSubmit: (_) {
                  calls++;
                  return result.future;
                },
              ),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('mobile-quick-add-field'));
    final submit = find.byKey(const ValueKey('mobile-quick-add-submit'));
    await tester.enterText(field, 'Leggi 31/02/2027');
    await tester.pump();
    expect(find.text('Data non valida'), findsOneWidget);
    expect(tester.widget<IconButton>(submit).onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls, 0);
    await tester.enterText(field, 'Leggi domani');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(submit).onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls, 1);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump();
    expect(field, findsOneWidget);
    result.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(submit).onPressed, isNotNull);
    expect(tester.widget<TextField>(field).controller!.text, 'Leggi domani');
    Navigator.of(tester.element(field)).pop();
    await tester.pumpAndSettle();
    expect(
      (await EditorDrafts(db).read('quick_add'))!['title'],
      'Leggi domani',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  });
}
