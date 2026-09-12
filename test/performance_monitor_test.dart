import 'package:deterministic_todo/services/memory_snapshot.dart';
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

  test('converte le metriche Android da KiB a byte', () {
    final snapshot = MemorySnapshot.fromKilobytes({
      'total_pss_kb': 120000,
      'java_heap_kb': 10000,
      'native_heap_kb': 30000,
      'graphics_kb': 5000,
    });
    expect(snapshot.totalPssBytes, 120000 * 1024);
    expect(snapshot.javaHeapBytes, 10000 * 1024);
    expect(snapshot.nativeHeapBytes, 30000 * 1024);
    expect(snapshot.graphicsBytes, 5000 * 1024);
  });
}
