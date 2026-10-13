import 'dart:typed_data';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/views/agenda_week_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Locks the look of the week and three-day grids: blocks, borders, clip
/// and ellipsis of titles, hour lines and folded nights (user report on
/// build 269, whose painted blocks looked different from build 268). The
/// goldens were checked pixel-identical to the build 268 page.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('it');
    final current = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _Tolerant(current.basedir.resolve('golden'));
  });

  AgendaEntry event(
    String id,
    String title,
    DateTime start,
    int minutes, {
    String calendar = 'a',
    bool unanswered = false,
  }) => AgendaEntry(
    instanceId: id,
    calendarIds: [calendar],
    title: title,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    allDay: false,
    unanswered: unanswered,
  );

  final monday = CivilDate(2026, 10, 12);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, 12 + day, hour, minute);
  final days = [
    for (var d = 0; d < 7; d++)
      AgendaDay(monday.addDays(d), [
        if (d == 0) event('a', 'Lab', at(0, 9), 60),
        if (d == 0) event('b', 'Visita', at(0, 10, 30), 90, calendar: 'b'),
        if (d == 1) event('c', 'Team', at(1, 9), 60, unanswered: true),
        if (d == 1) event('d', 'Uno', at(1, 11), 60),
        if (d == 1) event('e', 'Due', at(1, 11, 30), 60, calendar: 'b'),
        if (d == 2) event('f', 'Pranzo', at(2, 12), 30),
        if (d == 3) event('g', 'Psicoterapia', at(3, 14), 60, calendar: 'c'),
        if (d == 4) event('h', 'Tre parole qui', at(4, 16), 120),
      ]),
  ];

  for (final (name, count) in [('week', 7), ('three_days', 3)]) {
    for (final brightness in Brightness.values) {
      testWidgets('$name ${brightness.name} matches the golden', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(420, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: AgendaWeekPage(
                monday: count == 7 ? monday : monday.addDays(1),
                dayCount: count,
                today: CivilDate(2026, 10, 13),
                days: days,
                colors: const {
                  'a': Colors.pink,
                  'b': Colors.lightBlue,
                  'c': Colors.green,
                },
                onOpenDay: (_) {},
                onOpen: (_) async {},
                onCreate: null,
                now: () => DateTime(2026, 10, 13, 8, 30),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AgendaWeekPage),
          matchesGoldenFile('goldens/agenda_${name}_${brightness.name}.png'),
        );
      });
    }
  }
}

/// Anti-aliasing differs slightly between macOS and the Linux CI; layout,
/// colours or text changes move far more than 0.5% of the pixels.
class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= 0.005) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
