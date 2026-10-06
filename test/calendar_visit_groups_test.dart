import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/calendar_visit_groups.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/views/agenda_weeks_view.dart';
import 'package:deterministic_todo/ui/views/calendar_visit_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final day = CivilDate(2026, 10, 6);
AgendaEntry visit(
  int minute, {
  String calendar = 'clinic',
  String? title,
  int duration = 15,
  bool allDay = false,
  bool unanswered = false,
  String? taskId,
}) => AgendaEntry(
  instanceId: '$calendar:$minute:${title ?? 'visit'}',
  calendarIds: [calendar],
  title: title ?? 'Visita sintetica $minute',
  start: DateTime(2026, 10, 6, 9, minute),
  end: DateTime(2026, 10, 6, 9, minute + duration),
  allDay: allDay,
  unanswered: unanswered,
  taskId: taskId,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  test('three visits compress without changing objects, IDs or times', () {
    final entries = [visit(0), visit(15), visit(30)];
    final result = calendarVisitItems(entries, day);
    expect(result, hasLength(1));
    expect(result.single.grouped, true);
    expect(result.single.entries, orderedEquals(entries));
    expect(identical(result.single.entries[1], entries[1]), true);
    expect(result.single.end, DateTime(2026, 10, 6, 9, 45));
  });
  test('gaps, different calendars and unrelated titles separate groups', () {
    for (final entries in [
      [visit(0), visit(15), visit(45)],
      [visit(0), visit(15), visit(30, calendar: 'other')],
      [visit(0), visit(15, title: 'Riunione team'), visit(30)],
      [visit(0), visit(15)],
    ]) {
      expect(calendarVisitItems(entries, day).every((i) => !i.grouped), true);
    }
  });
  test('overlaps with other calendars are never hidden by a group', () {
    final entries = [
      visit(0),
      visit(5, duration: 50, calendar: 'other'),
      visit(15),
      visit(30),
      visit(45),
    ];
    expect(calendarVisitItems(entries, day).every((i) => !i.grouped), true);
  });
  test('all-day, tasks, pending requests and unanswered remain individual', () {
    for (final middle in [
      visit(15, allDay: true),
      visit(15, taskId: 'task'),
      visit(15, unanswered: true),
      visit(15, title: 'In attesa · Visita'),
    ]) {
      expect(
        calendarVisitItems([
          visit(0),
          middle,
          visit(30),
        ], day).every((i) => !i.grouped),
        true,
      );
    }
    expect(
      calendarVisitItems([
        visit(0),
        visit(15),
        visit(30),
      ], day.addDays(1)).every((i) => !i.grouped),
      true,
    );
  });
  test(
    'recognises common visit labels without grouping arbitrary meetings',
    () {
      final entries = [
        visit(0, title: 'Follow-up'),
        visit(15, title: 'Consultation'),
        visit(30, title: 'Assessment'),
      ];
      expect(calendarVisitItems(entries, day).single.grouped, true);
    },
  );
  testWidgets('group expands and selecting a visit opens that original only', (
    tester,
  ) async {
    final entries = [visit(0), visit(15), visit(30)];
    AgendaEntry? selected;
    var openedDay = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: 130,
              child: AgendaDayCell(
                date: day,
                today: day,
                entries: entries,
                colors: const {},
                groupVisits: true,
                onDay: (_) => openedDay = true,
                onOpenEntry: (entry) async {
                  selected = entry;
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CalendarVisitGroup), findsOneWidget);
    await tester.tap(find.byType(CalendarVisitGroup));
    await tester.pumpAndSettle();
    expect(openedDay, false);
    expect(find.text('09:15 – 09:30'), findsOneWidget);
    await tester.tap(find.text(entries[1].title));
    await tester.pumpAndSettle();
    expect(identical(selected, entries[1]), true);
  });
  testWidgets('ungrouped views retain every visit and overflow counts events', (
    tester,
  ) async {
    final entries = [visit(0), visit(15), visit(30)];
    Future<void> render(bool grouped, double height) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: height,
              child: AgendaDayCell(
                date: day,
                today: day,
                entries: entries,
                colors: const {},
                groupVisits: grouped,
                onDay: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await render(false, 150);
    expect(find.byType(CalendarVisitGroup), findsNothing);
    expect(find.text(entries[1].title), findsOneWidget);
    await render(true, 45);
    expect(find.text('+3'), findsOneWidget);
  });
}
