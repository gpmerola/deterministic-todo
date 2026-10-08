import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/views/agenda_colors.dart';
import 'package:deterministic_todo/ui/views/agenda_weeks_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  test(
    'calendar text retains contrast for pale, dark and mid-tone colours',
    () {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        for (final color in [
          Colors.blue,
          Colors.red,
          Colors.lime,
          Colors.yellow,
          Colors.grey,
          Colors.black,
          Colors.white,
          const Color(0xff808080),
        ]) {
          final fill = agendaEventFill(color, scheme);
          expect(contrast(agendaOnFill(fill), fill), greaterThanOrEqualTo(4.5));
          expect(
            contrast(agendaAccentText(color, scheme), scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(agendaOnFill(color), color),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  testWidgets('past and neighbouring-month event text is not faded', (
    tester,
  ) async {
    const day = CivilDate(2026, 10, 6);
    for (final outside in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              height: 130,
              child: AgendaDayCell(
                date: day,
                today: day.addDays(1),
                outside: outside,
                colors: const {},
                onDay: (_) {},
                entries: [
                  AgendaEntry(
                    instanceId: 'synthetic',
                    calendarIds: const ['calendar'],
                    title: 'Evento',
                    start: DateTime(2026, 10, 6, 9),
                    end: DateTime(2026, 10, 6, 10),
                    allDay: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Evento'), findsOneWidget);
      final fadedAncestors = tester.widgetList<Opacity>(
        find.ancestor(of: find.text('Evento'), matching: find.byType(Opacity)),
      );
      expect(fadedAncestors.any((widget) => widget.opacity < 1), false);
    }
  });
}
