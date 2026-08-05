import 'package:deterministic_todo/services/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la soglia frame lento corrisponde al budget di circa 60 Hz', () {
    expect(
      PerformanceMonitor.slowFrameThreshold,
      const Duration(microseconds: 16667),
    );
  });

  test('registra anche il budget frame del display a 120 Hz', () {
    expect(
      PerformanceMonitor.highRefreshSlowFrameThreshold,
      const Duration(microseconds: 8334),
    );
  });

  test('aggrega i frame prima di scrivere la diagnostica', () {
    expect(PerformanceMonitor.frameSampleSize, 600);
  });
}
