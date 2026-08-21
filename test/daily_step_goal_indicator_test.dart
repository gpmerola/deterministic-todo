import 'package:deterministic_todo/ui/daily_step_goal_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra progresso compatto e celebra il completamento', (
    tester,
  ) async {
    var steps = 5000;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              appBar: AppBar(
                actions: [
                  DailyStepGoalIndicator(
                    steps: steps,
                    goal: 10000,
                    onTap: () {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('5.0k'), findsOneWidget);
    update(() => steps = 10000);
    await tester.pump();
    expect(find.text('★'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Obiettivo giornaliero: 10000 di 10000 passi',
      ),
      findsOneWidget,
    );
  });
}
