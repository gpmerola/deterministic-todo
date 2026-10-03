import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/ui/views/task_order.dart';
import 'package:deterministic_todo/ui/views/today_view.dart';
import 'package:deterministic_todo/ui/views/upcoming_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Task _task(String id, {String? showDate, int priority = 1, int position = 0}) =>
    Task(
      id: id,
      title: 'Sintetica $id',
      itemKind: 'task',
      status: 'available',
      showDate: showDate,
      priority: priority,
      position: position,
      createdAt: 0,
      updatedAt: 0,
      logicalVersion: 1,
      deviceId: 'fixture',
    );

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('it'),
  supportedLocales: const [Locale('it')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: child),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('ordine: priorità, poi oggi, posizione e id', () {
    final tasks = [
      _task('c', showDate: '2026-09-01', position: 1),
      _task('b', showDate: '2026-09-27', position: 2),
      _task('a', showDate: '2026-09-01', priority: 4, position: 3),
    ]..sort((x, y) => compareByPriority(x, y, '2026-09-27'));
    expect(tasks.map((t) => t.id), ['a', 'b', 'c']);
    final upcoming = [
      _task('late', showDate: '2026-10-02', priority: 4),
      _task('soon', showDate: '2026-09-28'),
    ]..sort((x, y) => compareByDateThenPriority(x, y, '2026-09-27'));
    expect(upcoming.map((t) => t.id), ['soon', 'late']);
  });

  testWidgets('Oggi separa le arretrate con intestazioni', (tester) async {
    await tester.pumpWidget(
      _host(
        TodayTaskList(
          today: '2026-09-27',
          tasks: [
            _task('old', showDate: '2026-09-20'),
            _task('now', showDate: '2026-09-27'),
            _task('inbox'),
          ],
          tileBuilder: (task) => Text(task.id),
        ),
      ),
    );
    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(order, ['Arretrate', 'old', 'Oggi', 'now', 'inbox']);
  });

  testWidgets('Prossime mostra i giorni vuoti e carica altri giorni', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      _host(
        UpcomingTaskList(
          today: const CivilDate(2026, 9, 27),
          start: const CivilDate(2026, 9, 28),
          days: 2,
          tasks: [_task('x', showDate: '2026-09-29')],
          onLoadMore: () => loads++,
          tileBuilder: (task) => Text(task.id),
        ),
      ),
    );
    expect(find.text('Lunedì 28 settembre'), findsOneWidget);
    expect(find.text('Nessuna attività'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('upcoming-load-more')));
    expect(loads, 1);
  });

  testWidgets('a mezzanotte Oggi si aggiorna senza scritture', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'fixture');
    await repository.create('Domani sintetico', showDate: '2026-09-28');
    await db.delete(db.outboxEntries).go();
    final before = await db.select(db.tasks).getSingle();
    var now = DateTime(2026, 9, 27, 23, 59);
    await tester.pumpWidget(
      TodoApp(
        repository: repository,
        enablePlatformServices: false,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Domani sintetico'), findsNothing);

    now = DateTime(2026, 9, 28, 0, 0, 2);
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.text('Domani sintetico'), findsOneWidget);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(await db.select(db.tasks).getSingle(), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
