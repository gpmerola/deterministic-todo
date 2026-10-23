import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('l assistente sta nel menu Altro, non nella barra', (
    tester,
  ) async {
    var captured = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaHeader(
            loading: false,
            mode: AgendaViewMode.fourWeeks,
            onMode: (_) {},
            onChoose: () {},
            onCapture: () => captured++,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agenda-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-ai-capture')));
    await tester.pumpAndSettle();
    expect(captured, 1);
  });

  testWidgets('senza icona Oggi né contatore: i calendari sono in Altro', (
    tester,
  ) async {
    var chosen = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaHeader(
            loading: false,
            mode: AgendaViewMode.fourWeeks,
            filtered: true,
            onMode: (_) {},
            onChoose: () => chosen++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('agenda-today')), findsNothing);
    expect(find.byKey(const ValueKey('agenda-choose-calendars')), findsNothing);
    expect(find.textContaining('/'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agenda-more')));
    await tester.pumpAndSettle();
    expect(find.text('Calendari e filtri'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agenda-choose-calendars')));
    await tester.pumpAndSettle();
    expect(chosen, 1);
    await tester.tap(find.byKey(const ValueKey('agenda-mode')));
    await tester.pumpAndSettle();
    for (final removed in ['threeWeeks', 'month', 'list']) {
      expect(find.byKey(ValueKey('agenda-mode-$removed')), findsNothing);
    }
    expect(find.byKey(const ValueKey('agenda-mode-fourWeeks')), findsWidgets);
  });
}
