import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/views/agenda_week_view.dart';
import 'package:deterministic_todo/ui/views/agenda_weeks_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  for (final mode in ['week', 'threeDays', 'weeks']) {
    testWidgets('$mode exposes failed read and recovers with retry', (
      tester,
    ) async {
      var fail = true, calls = 0;
      Future<List<AgendaDay>> load(CivilDate first, int count) async {
        calls++;
        if (fail) throw StateError('synthetic failure');
        return [];
      }

      final today = CivilDate(2026, 10, 13);
      final Widget view = switch (mode) {
        'weeks' => AgendaWeeksView(
          today: today,
          revision: 0,
          loadDays: load,
          peekDays: (_, _) => null,
          colors: const {},
          onOpenDay: (_) {},
        ),
        _ => AgendaWeekView(
          today: today,
          revision: 0,
          loadDays: load,
          dayCount: mode == 'threeDays' ? 3 : 7,
          peekDays: (_, _) => null,
          colors: const {},
          onOpenDay: (_) {},
          onOpen: (_) async {},
        ),
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
      await tester.pumpAndSettle();
      expect(
        find.text('Calendario non aggiornato: lettura non riuscita.'),
        findsOneWidget,
      );
      final before = calls;
      fail = false;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(calls, before + 1);
      expect(find.text('Riprova'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
