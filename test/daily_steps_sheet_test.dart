import 'package:deterministic_todo/services/run_tracker_service.dart';
import 'package:deterministic_todo/ui/daily_steps_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12);

  test('etichetta lo stato della raccolta senza inventare passi', () {
    expect(stepCollectionLabel(null, now), 'Aggiornamento dei passi…');
    expect(
      stepCollectionLabel(
        DailyMovementProgress(
          day: '2026-10-03',
          steps: 10,
          collectionStatus: 'subscribed',
          lastImport: now.subtract(const Duration(hours: 7)),
        ),
        now,
      ),
      'Ultimo aggiornamento dei passi in ritardo.',
    );
    expect(
      stepCollectionLabel(
        const DailyMovementProgress(
          day: '2026-10-03',
          steps: 10,
          collectionStatus: 'subscribed',
          coverage: 'retention_gap',
        ),
        now,
      ),
      'Conteggio attivo · alcuni intervalli non recuperabili.',
    );
    expect(
      stepCollectionLabel(
        const DailyMovementProgress(
          day: '2026-10-03',
          steps: 0,
          collectionStatus: 'api_error_17',
        ),
        now,
      ),
      startsWith('Conteggio non disponibile'),
    );
  });

  testWidgets('mostra passi e chiede il permesso solo se manca', (
    tester,
  ) async {
    var enabled = 0;
    var edited = 0;
    var status = 'subscribed';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDailyStepsSheet(
              context,
              progress: DailyMovementProgress(
                day: '2026-10-03',
                steps: 6543,
                collectionStatus: status,
              ),
              goal: 10000,
              enableSteps: () async => enabled++,
              editGoal: () => edited++,
            ),
            child: const Text('anello'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('anello'));
    await tester.pumpAndSettle();
    expect(find.text('6.543 / 10.000'), findsOneWidget);
    expect(find.text('Abilita conteggio passi'), findsNothing);
    await tester.tap(find.text('Cambia obiettivo'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    expect(find.text('6.543 / 10.000'), findsNothing);

    status = 'permission_required';
    await tester.tap(find.text('anello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abilita conteggio passi'));
    await tester.pumpAndSettle();
    expect(enabled, 1);
    expect(find.text('6.543 / 10.000'), findsNothing);
  });
}
