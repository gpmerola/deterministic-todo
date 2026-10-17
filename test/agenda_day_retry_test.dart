import 'dart:async';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/views/agenda_day_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  for (final cached in [false, true]) {
    testWidgets('day read fails, retains preview=$cached and retries once', (
      tester,
    ) async {
      final date = CivilDate(2026, 10, 13);
      final preview = AgendaDay(date, [
        AgendaEntry(
          instanceId: 'fixture',
          calendarIds: const ['synthetic'],
          title: 'Synthetic preview',
          start: DateTime(2026, 10, 13, 9),
          end: DateTime(2026, 10, 13, 10),
          allDay: false,
        ),
      ]);
      var calls = 0;
      final retry = Completer<List<AgendaDay>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaDayTimeline(
              day: date,
              today: date,
              colors: const {},
              loadDays: (_, _) {
                calls++;
                return calls == 1
                    ? Future.error(StateError('private details'))
                    : retry.future;
              },
              peekDays: (_, _) => cached ? [preview] : null,
              onOpen: (_) async {},
              onCreate: null,
              now: () => DateTime(2026, 10, 13, 9),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Calendario non aggiornato: lettura non riuscita.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Synthetic preview'),
        cached ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Riprova'));
      await tester.pump();
      await tester.tap(find.text('Riprova'));
      expect(calls, 2);
      expect(
        find.text('Synthetic preview'),
        cached ? findsOneWidget : findsNothing,
      );
      // An empty successful response is a usable empty day, not a spinner.
      retry.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Riprova'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Synthetic preview'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
