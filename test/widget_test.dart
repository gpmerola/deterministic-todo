import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creazione rapida con Invio aggiorna Inbox', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.enterText(find.byType(TextField).first, 'Comprare il pane');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Comprare il pane'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Impostazioni è raggiungibile su uno schermo Android', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.text('Oggi'), findsWidgets);
    expect(find.text('Inbox'), findsNothing);
    expect(find.text('In attesa'), findsNothing);
    expect(find.text('Progetti'), findsOneWidget);
    expect(find.text('Completate'), findsNothing);
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pump();

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Attività completate'), findsOneWidget);
    expect(find.byTooltip('Indietro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('i link Todoist mostrano la parola senza URL esteso', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TodoistLinkText('[Tracker](https://example.com/path)'),
        ),
      ),
    );

    expect(find.text('Tracker'), findsOneWidget);
    expect(find.textContaining('https://example.com'), findsNothing);
  });

  testWidgets('il composer mobile crea dal foglio inferiore', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      'Visita domani',
    );
    await tester.pump();
    expect(find.textContaining('Pianificata:'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
    await tester.pumpAndSettle();

    final task = (await db.select(db.tasks).get()).single;
    expect(task.title, 'Visita');
    expect(task.showDate, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
