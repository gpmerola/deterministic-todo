import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/ui/todoist_link_text.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la descrizione accessibile non dipende solo dal colore', () {
    final task = Task(
      id: 'task-a',
      title: 'Vitamine',
      itemKind: 'task',
      status: TaskStatus.available.name,
      showDate: '2026-08-08',
      priority: 4,
      position: 1,
      recurrence: const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      ).encode(),
      createdAt: 1,
      updatedAt: 1,
      logicalVersion: 1,
      deviceId: 'device-a',
    );

    expect(taskAccessibilityLabel(task), contains('Priorità P1'));
    expect(taskAccessibilityLabel(task), contains('Ripetizione ogni giorno'));
    expect(taskAccessibilityLabel(task), contains('Data 2026-08-08'));
  });

  testWidgets('target tattili e semantica restano accessibili', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create(
      'Prioritaria',
      status: TaskStatus.available,
      showDate: '2026-08-08',
      recurrence: const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      ).encode(),
      priority: 4,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: TodoApp(repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final settingsSize = tester.getSize(find.byTooltip('Impostazioni'));
    expect(settingsSize.width, greaterThanOrEqualTo(48));
    expect(settingsSize.height, greaterThanOrEqualTo(48));
    final taskSemantics = tester.getSemantics(find.byType(TaskTile));
    expect(taskSemantics.label, contains('Priorità P1'));
    expect(taskSemantics.label, contains('Ripetizione ogni giorno'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('creazione rapida con Invio aggiorna Inbox', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      'Comprare il pane',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Comprare il pane'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Oggi esclude il backlog non pianificato dei progetti', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final projectId = await repository.createProject('Lavoro');
    await repository.create('Backlog progetto', projectId: projectId);
    await repository.create('Inbox personale');

    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.text('Backlog progetto'), findsNothing);
    expect(find.text('Inbox personale'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
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

    expect(find.text('Privacy'), findsNothing);
    expect(find.text('Attività completate'), findsOneWidget);
    expect(find.text('Dati e manutenzione'), findsOneWidget);
    expect(find.text('Importa da Todoist'), findsNothing);
    expect(find.byTooltip('Indietro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Chrome largo usa una navigazione desktop minimale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');

    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Inbox'), findsNothing);
    expect(find.text('In attesa'), findsNothing);
    expect(find.text('Oggi'), findsWidgets);
    expect(find.text('Prossime'), findsOneWidget);
    expect(find.text('Progetti'), findsOneWidget);
    expect(find.byTooltip('Nuova attività (Ctrl/⌘ N)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il comando universale crea con + e linguaggio naturale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Comando universale (Ctrl/⌘ K)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '+ Report domani');
    await tester.pump();
    await tester.tap(find.text('Report'));
    await tester.pump();

    final task = await db.select(db.tasks).getSingle();
    expect(task.title, 'Report');
    expect(task.showDate, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump();
  });

  testWidgets('il desktop mostra il dettaglio laterale opzionale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Apri dettaglio');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Apri dettaglio'));
    await tester.pumpAndSettle();
    expect(find.text('Dettagli'), findsOneWidget);
    expect(find.byTooltip('Chiudi dettagli'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-editor-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('task-editor-title')),
      'Dettaglio modificato',
    );
    await tester.tap(find.byKey(const ValueKey('task-editor-title')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Dettaglio modificato'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
    await tester.pump();
  });

  testWidgets('le transizioni UI sono brevi e non coinvolgono il composer', (
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

    final pageMotion = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('page-motion')),
    );
    final titleMotion = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('appbar-title-motion')),
    );
    expect(
      pageMotion.duration,
      lessThanOrEqualTo(const Duration(milliseconds: 150)),
    );
    expect(
      titleMotion.duration,
      lessThanOrEqualTo(const Duration(milliseconds: 120)),
    );

    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
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

  testWidgets('il Cestino nelle Impostazioni ripristina le attività', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final id = await repository.create('Da recuperare');
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    await repository.softDelete(task);
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cestino'));
    await tester.pumpAndSettle();

    expect(find.text('Da recuperare'), findsOneWidget);
    await tester.tap(find.byTooltip('Ripristina').first);
    await tester.pumpAndSettle();
    expect(find.text('Cestino vuoto'), findsOneWidget);
    expect(
      (await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(id))).getSingle()).deletedAt,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('la descrizione Todoist appare sotto il titolo con link puliti', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final id = await repository.create('Update PhD');
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    await repository.updateDetails(
      task,
      title: task.title,
      notes: 'Methods paper [Paper1](https://example.com/paper)',
    );
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.text('Update PhD'), findsOneWidget);
    expect(find.textContaining('Methods paper Paper1'), findsOneWidget);
    expect(find.textContaining('https://example.com'), findsNothing);
    await tester.tap(find.text('Update PhD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Altri dettagli'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Paper1'), findsOneWidget);
    expect(find.textContaining('https://example.com'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('lo swipe nel cestino offre Annulla e ripristina la task', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Non eliminarmi');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.drag(find.text('Non eliminarmi'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Spostata nel cestino'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Non eliminarmi'), findsOneWidget);
    expect((await db.select(db.tasks).getSingle()).deletedAt, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('l annuncio con Undo scompare automaticamente', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Annuncio temporaneo');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.drag(find.text('Annuncio temporaneo'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Spostata nel cestino'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Spostata nel cestino'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('lo swipe elimina solo verso sinistra oltre una soglia lunga', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Swipe sicuro');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    expect(dismissible.direction, DismissDirection.endToStart);
    expect(
      dismissible.dismissThresholds[DismissDirection.endToStart],
      greaterThan(0.6),
    );

    expect((await db.select(db.tasks).getSingle()).deletedAt, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('lo swipe iniziato sulla spunta non muove né elimina la task', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Spunta protetta');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('completion-no-swipe-zone'))),
    );
    await gesture.moveBy(const Offset(-500, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Spunta protetta'), findsOneWidget);
    expect(find.text('Spostata nel cestino'), findsNothing);
    expect((await db.select(db.tasks).getSingle()).deletedAt, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
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
    final composer = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile-quick-add-field')),
    );
    expect(composer.decoration?.helperText, isNotNull);
    expect(composer.decoration?.helperText, isNot(contains('Pianificata')));
    await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
    await tester.pumpAndSettle();

    final task = (await db.select(db.tasks).get()).single;
    expect(task.title, 'Visita');
    expect(task.showDate, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il composer desktop usa una riga e Invio crea la task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Nuova attività (Ctrl/⌘ N)'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile-quick-add-field')),
    );
    expect(field.maxLines, 1);
    await tester.enterText(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      'Creata con invio',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect((await db.select(db.tasks).getSingle()).title, 'Creata con invio');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il menu visibile manda una task nel Cestino con Undo', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Elimina intuitivamente');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Azioni attività'));
    await tester.pumpAndSettle();
    final deleteItem = find.widgetWithText(PopupMenuItem<String>, 'Cestino');
    final deleteRect = tester.getRect(deleteItem);
    await tester.tapAt(Offset(deleteRect.left + 24, deleteRect.center.dy));
    await tester.pump();
    expect((await db.select(db.tasks).getSingle()).deletedAt, isNotNull);
    expect(find.text('Annulla'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il composer mobile appare al primo frame senza attendere I/O', (
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

    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('ricorrenza e priorità sono riconoscibili nella lista', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create(
      'Report settimanale',
      showDate: '2026-08-09',
      recurrence: 'calendar:week:1',
      priority: 4,
    );

    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.textContaining('ogni domenica'), findsOneWidget);
    expect(find.textContaining('Mostra'), findsNothing);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(checkbox.side!.color, Colors.red);
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(
        ValueKey('task-surface-${(await db.select(db.tasks).getSingle()).id}'),
      ),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect((decoration.border! as Border).left.width, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('le attività sono ordinate automaticamente per priorità', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('P4', priority: 1);
    await repository.create('P1', priority: 4);
    await repository.create('P2', priority: 3);
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('P1')).dy,
      lessThan(tester.getTopLeft(find.text('P2')).dy),
    );
    expect(
      tester.getTopLeft(find.text('P2')).dy,
      lessThan(tester.getTopLeft(find.text('P4')).dy),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('Progetti naviga da elenco minimale al dettaglio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final projectId = await repository.createProject('Casa');
    await repository.create('Pulizie', projectId: projectId);
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    await tester.tap(find.text('Progetti'));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('I miei progetti'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Pulizie'), findsNothing);
    expect(find.textContaining('1 attività'), findsNothing);

    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.text('Pulizie'), findsOneWidget);
    expect(find.byKey(const ValueKey('back-to-projects')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('I miei progetti'), findsOneWidget);
    expect(find.text('Pulizie'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('nei progetti Aggiungi usa lo stesso composer rapido', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final projectId = await repository.createProject('Casa');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    await tester.tap(find.text('Progetti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    expect(projectId, isNotEmpty);
    await db.close();
  });

  testWidgets(
    'il menu progetto consente spostamento ed eliminazione con Undo',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TaskRepository(db, deviceId: 'test-device');
      final firstId = await repository.createProject('Primo');
      await repository.createProject('Secondo');
      await tester.pumpWidget(TodoApp(repository: repository));
      await tester.pump();
      await tester.tap(find.text('Progetti'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('project-actions-$firstId')));
      await tester.pumpAndSettle();
      expect(find.text('Rinomina'), findsOneWidget);
      expect(find.text('Sposta giù'), findsOneWidget);
      expect(find.text('Elimina'), findsOneWidget);
      await tester.tap(find.text('Sposta giù'));
      await tester.pumpAndSettle();
      final ordered = await (db.select(
        db.projects,
      )..orderBy([(row) => OrderingTerm(expression: row.position)])).get();
      expect(ordered.last.id, firstId);

      await tester.tap(find.byKey(ValueKey('project-actions-$firstId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      expect(find.textContaining('eliminato'), findsOneWidget);
      expect(find.text('Annulla'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(find.text('Primo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    },
  );

  testWidgets('chiudendo la tastiera il composer mobile si chiude subito', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      findsOneWidget,
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-quick-add-field')), findsNothing);
    await db.close();
  });

  testWidgets('il composer non segue gli assestamenti della tastiera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pumpAndSettle();

    Padding composerPadding() => tester.widget<Padding>(
      find.byKey(const ValueKey('mobile-quick-add-keyboard-padding')),
    );
    expect((composerPadding().padding as EdgeInsets).bottom, 312);

    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    expect((composerPadding().padding as EdgeInsets).bottom, 312);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il composer aggiunge subito una descrizione opzionale', (
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

    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-quick-add-notes')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-quick-add-field')),
      'Leggi articolo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile-quick-add-notes-field')),
      'Concentrati sui metodi',
    );
    await tester.tap(find.byKey(const ValueKey('mobile-quick-add-priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-quick-add-submit')));
    await tester.pumpAndSettle();

    final task = await db.select(db.tasks).getSingle();
    expect(task.notes, 'Concentrati sui metodi');
    expect(task.priority, 4);

    await tester.tap(find.byTooltip('Nuova attività'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Nessuna priorità'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('il completamento anima prima di aggiornare il database', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final taskId = await repository.create('Animami');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump(const Duration(milliseconds: 50));
    expect((await db.select(db.tasks).getSingle()).status, 'inbox');
    expect(find.byKey(const ValueKey('completed-check')), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(ValueKey('completion-opacity-$taskId')),
          )
          .opacity,
      0,
    );
    expect(find.byType(AnimatedSlide), findsNothing);
    await tester.pump(const Duration(milliseconds: 130));
    expect((await db.select(db.tasks).getSingle()).status, 'inbox');

    await tester.pumpAndSettle();
    expect((await db.select(db.tasks).getSingle()).status, 'completed');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('i vecchi riferimenti restano accessibili come attività', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create(
      'Vecchio riferimento',
      notes: 'Nota conservata',
      itemKind: 'reference',
    );
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    expect(find.text('Riferimenti'), findsNothing);
    expect(find.text('Vecchio riferimento'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('Progetti'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('la modifica attività usa un foglio inferiore compatto', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Apri editor');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Apri editor'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('task-editor-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-editor-save')), findsOneWidget);
    expect(find.text('Ora'), findsNothing);
    expect(find.text('Stato'), findsNothing);
    expect(find.text('Scadenza'), findsNothing);
    expect(find.text('Altri dettagli'), findsOneWidget);
    expect(find.text('Note'), findsNothing);
    expect(
      tester.getSize(find.byType(TaskEditor)).height,
      lessThanOrEqualTo(460),
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-editor-title')),
      'Editor confermato con Invio',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      (await db.select(db.tasks).getSingle()).title,
      'Editor confermato con Invio',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('Data nell editor riprogramma e salva l attività', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Riprogramma attività');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Riprogramma attività'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Data'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DatePickerDialog), findsOneWidget);
    final target = DateTime.now().add(const Duration(days: 10));
    await tester.tap(find.text('${target.day}').last);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('task-editor-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await db.select(db.tasks).getSingle();
    expect(saved.showDate, CivilDate.fromDateTime(target).toString());
    expect(saved.status, TaskStatus.scheduled.name);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('domani nell editor riprogramma e viene rimosso dal titolo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await repository.create('Riprogramma attività');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Riprogramma attività'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-editor-title')),
      'Riprogramma attività domani',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-editor-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await db.select(db.tasks).getSingle();
    expect(saved.title, 'Riprogramma attività');
    expect(
      saved.showDate,
      CivilDate.fromDateTime(
        DateTime.now().add(const Duration(days: 1)),
      ).toString(),
    );
    expect(saved.status, TaskStatus.scheduled.name);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('Inbox Todoist non appare come progetto separato', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    final inboxId = await repository.createProject('Inbox');
    await repository.create('Dal contenitore Inbox', projectId: inboxId);
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Dal contenitore Inbox'), findsOneWidget);
    await tester.tap(find.text('Progetti'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsNothing);
    expect(find.text('Nessun progetto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets(
    'Prossime mostra una timeline senza quadratini e indica i giorni vuoti',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TaskRepository(db, deviceId: 'test-device');
      final tomorrow = CivilDate.fromDateTime(
        DateTime.now().add(const Duration(days: 1)),
      ).toString();
      await repository.create(
        'Attività domani',
        status: TaskStatus.scheduled,
        showDate: tomorrow,
      );
      await tester.pumpWidget(TodoApp(repository: repository));
      await tester.pump();
      await tester.tap(find.text('Prossime'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Tutte'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Attività domani'), findsOneWidget);
      expect(find.text('Nessuna attività'), findsWidgets);
      expect(find.byKey(const ValueKey('jump-to-future-date')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    },
  );

  testWidgets('indietro Android torna alla vista precedente senza uscire', (
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

    await tester.tap(find.text('Prossime'));
    await tester.pump();
    expect(find.byKey(const ValueKey('jump-to-future-date')), findsOneWidget);
    await tester.tap(find.text('Progetti'));
    await tester.pump();
    expect(find.text('Nessun progetto'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const ValueKey('jump-to-future-date')), findsOneWidget);
    expect(find.text('Nessun progetto'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Oggi'), findsWidgets);
    expect(find.byKey(const ValueKey('jump-to-future-date')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('Impostazioni espone Salute dati senza clutter nella home', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    await tester.pump();
    expect(find.text('Salute dati'), findsNothing);

    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pump();
    expect(find.text('Salute dati'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataHealthView(repository: repository)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Modifiche in attesa'), findsOneWidget);
    expect(find.text('Dati locali'), findsOneWidget);
    expect(find.text('Ultimo backup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });

  testWidgets('il tema usa il rosso di marca su chiaro e scuro', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'test-device');
    await tester.pumpWidget(TodoApp(repository: repository));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.colorScheme.primary, TodoApp.brandRed);
    expect(app.darkTheme?.colorScheme.primary, TodoApp.brandRed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
