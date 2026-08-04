import 'package:deterministic_todo/services/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la soglia frame lento corrisponde al budget di circa 60 Hz', () {
    expect(
      PerformanceMonitor.slowFrameThreshold,
      const Duration(microseconds: 16667),
    );
  });
}
