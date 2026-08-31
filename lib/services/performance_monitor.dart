import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/scheduler.dart';

import '../data/local/database.dart';
import '../domain/task.dart';
import 'diagnostic_log_service.dart';
import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

class PerformanceMonitor {
  PerformanceMonitor._();

  static final instance = PerformanceMonitor._();
  static const slowFrameThreshold = Duration(microseconds: 16667);
  static const highRefreshSlowFrameThreshold = Duration(microseconds: 8334);
  static const frameSampleSize = 600;

  final List<FrameTiming> _frames = [];
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(timings);
    if (_frames.length >= frameSampleSize) unawaited(flushFrames());
  }

  Future<void> flushFrames() async {
    if (_frames.isEmpty) return;
    final sample = List<FrameTiming>.of(_frames);
    _frames.clear();
    try {
      await _writeFrames(sample);
    } on Object {
      // La profilazione non deve mai interferire con l'app.
    }
  }

  Future<void> _writeFrames(List<FrameTiming> sample) async {
    final build = sample.map((frame) => frame.buildDuration.inMicroseconds);
    final raster = sample.map((frame) => frame.rasterDuration.inMicroseconds);
    final slow = sample.where((frame) => frame.totalSpan > slowFrameThreshold);
    final highRefreshSlow = sample.where(
      (frame) => frame.totalSpan > highRefreshSlowFrameThreshold,
    );
    await DiagnosticLogService.instance.event(
      'frame_sample',
      fields: {
        'frames': sample.length,
        'slow_frames': slow.length,
        'slow_frames_8ms': highRefreshSlow.length,
        'build_us_avg': _average(build),
        'build_us_max': build.reduce(_max),
        'raster_us_avg': _average(raster),
        'raster_us_max': raster.reduce(_max),
      },
    );
  }

  Future<void> snapshot(String phase, AppDatabase db, {int? durationMs}) async {
    try {
      await _writeSnapshot(phase, db, durationMs: durationMs);
    } on Object {
      // La profilazione non deve mai interferire con l'app.
    }
  }

  Future<void> _writeSnapshot(
    String phase,
    AppDatabase db, {
    int? durationMs,
  }) async {
    final memory = await readMemorySnapshot();
    final activeCount = db.tasks.id.count(
      filter:
          db.tasks.deletedAt.isNull() &
          db.tasks.status.equals(TaskStatus.completed.name).not(),
    );
    final completedCount = db.tasks.id.count(
      filter:
          db.tasks.deletedAt.isNull() &
          db.tasks.status.equals(TaskStatus.completed.name),
    );
    final taskCounts = db.selectOnly(db.tasks)
      ..addColumns([activeCount, completedCount]);
    final counts = await taskCounts.getSingle();
    final outboxCount = db.outboxEntries.operationId.count();
    final outboxQuery = db.selectOnly(db.outboxEntries)
      ..addColumns([outboxCount]);
    await DiagnosticLogService.instance.event(
      'performance_snapshot',
      fields: {
        'phase': phase,
        'rss_bytes': currentRssBytes,
        'total_pss_bytes': ?memory?.totalPssBytes,
        'java_heap_bytes': ?memory?.javaHeapBytes,
        'native_heap_bytes': ?memory?.nativeHeapBytes,
        'graphics_bytes': ?memory?.graphicsBytes,
        'db_bytes': await databaseSizeBytes(),
        'active_tasks': counts.read(activeCount) ?? 0,
        'completed_tasks': counts.read(completedCount) ?? 0,
        'outbox': (await outboxQuery.getSingle()).read(outboxCount) ?? 0,
        'duration_ms': ?durationMs,
      },
    );
  }

  int _average(Iterable<int> values) {
    var count = 0;
    var total = 0;
    for (final value in values) {
      count++;
      total += value;
    }
    return count == 0 ? 0 : total ~/ count;
  }

  int _max(int left, int right) => left > right ? left : right;
}
