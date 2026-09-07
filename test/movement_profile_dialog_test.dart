import 'package:deterministic_todo/ui/movement_profile_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profilo valida i limiti e accetta la virgola decimale', (
    tester,
  ) async {
    Map<String, double>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<Map<String, double>>(
                  context: context,
                  builder: (_) => const MovementProfileDialog(values: {}),
                );
              },
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('Inserisci un valore'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '75,5');
    await tester.enterText(find.byType(TextFormField).at(1), '0,80');
    await tester.enterText(find.byType(TextFormField).at(2), '1,20');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(saved, {
      'weight_kg': 75.5,
      'walking_stride_meters': .8,
      'running_stride_meters': 1.2,
    });
  });
}
