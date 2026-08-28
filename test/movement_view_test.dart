import 'package:deterministic_todo/services/run_tracker_service.dart';
import 'package:deterministic_todo/ui/movement_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.deterministic.todo/run_tracker');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Movimento è integrato e avvia senza aprire una seconda pagina', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'movementState') {
            return <String, Object?>{
              'recording': false,
              'session_id': 0,
              'activity_type': '',
              'started_at_ms': 0,
              'distance_m': 0.0,
              'session_steps': 0,
              'accuracy_m': 0.0,
              'gps_status': 'GPS spento',
              'passive_active': true,
              'drive_configured': true,
              'automatic_status': 'Monitor passivo attivo',
              'drive_status': 'Pronto',
            };
          }
          if (call.method == 'startMovement') return 'started';
          return null;
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MovementView(
            dailyMovement: DailyMovementProgress(
              day: '2026-08-21',
              steps: 646,
              distanceMeters: 465,
              calories: 22,
              updatedAt: DateTime(2026, 8, 21),
              phoneSteps: 646,
              bipSteps: 600,
              source: 'phone_step_counter',
            ),
            stepGoal: 10000,
            refreshDailyMovement: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Registra attività'), findsOneWidget);
    expect(find.text('646 / 10.000 passi'), findsOneWidget);
    expect(find.text('Apri Movimento'), findsNothing);

    await tester.tap(find.text('Camminata'));
    await tester.pump();
    expect(calls, contains('startMovement'));
    expect(calls, isNot(contains('open')));

    await tester.pumpWidget(const SizedBox());
  });
}
