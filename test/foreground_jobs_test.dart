import 'dart:async';

import 'package:deterministic_todo/ui/shell/foreground_jobs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slow or failing jobs do not delay backup and maintenance', () async {
    final failures = <String>[];
    final jobs = ForegroundJobs(onFailure: (name, _) => failures.add(name));
    addTearDown(jobs.dispose);
    final update = Completer<void>();
    final held = jobs.run('updates', () => update.future, timeout: null);
    final failing = jobs.run('steps', () => throw StateError('synthetic'));
    var backup = false, maintenance = false;
    await jobs.run('backup', () async {
      backup = true;
    });
    await jobs.run('maintenance', () async {
      maintenance = true;
    });
    await failing;
    expect(backup && maintenance, isTrue);
    expect(failures, ['steps']);
    update.complete();
    await held;
  });

  testWidgets('timeout retains lease; late errors handled; next run allowed', (
    tester,
  ) async {
    final failures = <Object>[];
    final jobs = ForegroundJobs(onFailure: (_, error) => failures.add(error));
    final pending = Completer<void>();
    var calls = 0;
    final first = jobs.run('backup', () {
      calls++;
      return pending.future;
    }, timeout: const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await first;
    await jobs.run('backup', () async {
      calls++;
    });
    expect(calls, 1);
    expect(failures.single, isA<TimeoutException>());
    pending.completeError(StateError('late'));
    await tester.pump();
    expect(failures.last, isA<StateError>());
    await jobs.run('backup', () async {
      calls++;
    });
    expect(calls, 2);
    jobs.dispose();
  });

  test('dispose prevents new work and silences late diagnostics', () async {
    final jobs = ForegroundJobs(onFailure: (_, _) => fail('disposed'));
    final pending = Completer<void>();
    final work = jobs.run('steps', () => pending.future);
    jobs.dispose();
    pending.completeError(StateError('late'));
    await work;
    await jobs.run('steps', () async => fail('new work'));
  });
}
