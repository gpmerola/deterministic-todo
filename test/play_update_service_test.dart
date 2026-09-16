import 'package:deterministic_todo/services/play_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps every native Play update status', () async {
    for (final status in PlayUpdateStatus.values) {
      final service = PlayUpdateService(
        invoker: (_) async => {'status': status.name},
      );
      expect(await service.check(startIfAvailable: true), status);
    }
  });

  test('passes whether the update flow should start', () async {
    bool? received;
    final service = PlayUpdateService(
      invoker: (start) async {
        received = start;
        return {'status': 'unavailable'};
      },
    );
    await service.check(startIfAvailable: true);
    expect(received, isTrue);
  });

  test('turns bridge failures and unknown values into error', () async {
    final failing = PlayUpdateService(
      invoker: (_) => Future<Object?>.error(StateError('native failure')),
    );
    final unknown = PlayUpdateService(invoker: (_) async => 'future-status');

    expect(await failing.check(startIfAvailable: true), PlayUpdateStatus.error);
    expect(await unknown.check(startIfAvailable: true), PlayUpdateStatus.error);
  });
}
