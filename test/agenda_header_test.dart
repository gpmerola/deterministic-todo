import 'package:deterministic_todo/domain/task.dart';
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
            visible: 1,
            total: 1,
            loading: false,
            mode: AgendaViewMode.fourWeeks,
            onMode: (_) {},
            onToday: () {},
            today: const CivilDate(2026, 10, 23),
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
}
