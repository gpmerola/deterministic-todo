class MemorySnapshot {
  const MemorySnapshot({
    required this.totalPssBytes,
    required this.javaHeapBytes,
    required this.nativeHeapBytes,
    required this.graphicsBytes,
  });

  final int totalPssBytes;
  final int javaHeapBytes;
  final int nativeHeapBytes;
  final int graphicsBytes;

  factory MemorySnapshot.fromKilobytes(Map<String, int> values) =>
      MemorySnapshot(
        totalPssBytes: _bytes(values['total_pss_kb']),
        javaHeapBytes: _bytes(values['java_heap_kb']),
        nativeHeapBytes: _bytes(values['native_heap_kb']),
        graphicsBytes: _bytes(values['graphics_kb']),
      );

  static int _bytes(int? kilobytes) => (kilobytes ?? 0) * 1024;
}
