// Opt-in release harness. Never imports main.dart or opens the app database.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' show FramePhase;

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/auto_backup_service.dart';
import 'package:deterministic_todo/ui/views/agenda_week_view.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'legacy/agenda_week_view_b267.dart';

/// `calendar`: only the week-view scroll, alternating the build 267 view
/// (legacy) and the current one in the same process, no backup fixtures.
const scenario = String.fromEnvironment(
  'TODO_PERF_SCENARIO',
  defaultValue: 'all',
);

void emit(Map<String, Object> values) =>
    debugPrint('TODO_PERF: ${jsonEncode(values)}');

Future<void> main() async {
  final boot = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  if (!const bool.fromEnvironment('TODO_VALIDATION') ||
      !package.packageName.endsWith('.dev.validation')) {
    throw StateError('Isolated validation package required');
  }
  await initializeDateFormatting('it');
  runApp(const MaterialApp(home: _Benchmark()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    emit({
      'phase': 'harness_first_frame',
      'duration_us': boot.elapsedMicroseconds,
    });
  });
}

class _Benchmark extends StatefulWidget {
  const _Benchmark();
  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark> {
  var pages = PageController(initialPage: AgendaWeekView.weeksBack);
  bool legacy = false;
  final date = CivilDate(2026, 10, 13);
  List<FrameTiming> frames = [];
  int? startUs;
  int? endUs;
  int revision = 0;
  bool running = true;
  List<AgendaDay> days(CivilDate first, int count) => [
    for (var d = 0; d < count; d++)
      AgendaDay(first.addDays(d), [
        for (var i = 0; i < 12; i++)
          AgendaEntry(
            instanceId: '${first.addDays(d)}-$i',
            calendarIds: const ['synthetic'],
            title: 'Synthetic event $i',
            start: first.addDays(d).asLocalDate.add(Duration(hours: 7 + i)),
            end: first
                .addDays(d)
                .asLocalDate
                .add(Duration(hours: 7 + i, minutes: 45)),
            allDay: false,
          ),
      ]),
  ];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<FrameTiming> batch) => frames.addAll(batch);
  void begin() {
    frames = [];
    startUs = Timeline.now;
    endUs = null;
  }

  Future<Map<String, Object>> end() async {
    endUs = Timeline.now;
    // Release FrameTiming callbacks arrive in batches, up to about a second.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final sample = frames.where((f) {
      final at = f.timestampInMicroseconds(FramePhase.buildStart);
      return at >= startUs! && at <= endUs!;
    }).toList();
    int p95(Iterable<int> input) {
      final sorted = input.toList()..sort();
      return sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * .95).ceil()];
    }

    return {
      'frames': sample.length,
      'build_max_us': sample.fold<int>(
        0,
        (v, f) => max(v, f.buildDuration.inMicroseconds),
      ),
      'raster_max_us': sample.fold<int>(
        0,
        (v, f) => max(v, f.rasterDuration.inMicroseconds),
      ),
      'build_p95_us': p95(sample.map((f) => f.buildDuration.inMicroseconds)),
      'raster_p95_us': p95(sample.map((f) => f.rasterDuration.inMicroseconds)),
      'frames_over_16ms': sample
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 16667 ||
                f.rasterDuration.inMicroseconds > 16667,
          )
          .length,
      'frames_over_8ms': sample
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 8334 ||
                f.rasterDuration.inMicroseconds > 8334,
          )
          .length,
    };
  }

  Future<void> scroll() async {
    final initial = pages.page!.round();
    for (var i = 1; i <= 6; i++) {
      await pages.animateToPage(
        initial + (i.isOdd ? 1 : 0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
    }
  }

  Future<void> _run() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 1));
      final calendarOnly = scenario == 'calendar';
      for (var sample = 0; sample < (calendarOnly ? 12 : 3); sample++) {
        if (calendarOnly) {
          // A fresh view and controller per sample; one unmeasured pass
          // loads both pages, so each variant is measured warm.
          final old = pages;
          setState(() {
            legacy = sample.isEven;
            pages = PageController(initialPage: AgendaWeekView.weeksBack);
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
          old.dispose();
          await scroll();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        begin();
        await scroll();
        emit({
          'phase': 'calendar_scroll',
          'sample': sample,
          'events_per_day': 12,
          if (calendarOnly) 'variant': legacy ? 'build_267' : 'current',
          ...await end(),
        });
      }
      for (final count in calendarOnly ? <int>[] : [100, 1000, 10000]) {
        final folder = await Directory.systemTemp.createTemp('todo-synthetic-');
        final db = AppDatabase.forTesting(
          NativeDatabase.createInBackground(
            File('${folder.path}/fixture.sqlite'),
          ),
        );
        try {
          await db.batch(
            (batch) => batch.insertAll(db.tasks, [
              for (var i = 0; i < count; i++)
                TasksCompanion.insert(
                  id: 'fixture-$i',
                  title: 'Synthetic backup $i',
                  notes: Value('x' * 1000),
                  status: 'scheduled',
                  position: i,
                  createdAt: i,
                  updatedAt: i,
                  deviceId: 'synthetic',
                ),
            ]),
          );
          final store = _CaptureStore();
          final service = AutoBackupService(db, store: store);
          for (var sample = 0; sample < 3; sample++) {
            begin();
            final movement = scroll();
            // Start backup while an actual page animation is in progress.
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final watch = Stopwatch()..start();
            final before = ProcessInfo.currentRss;
            var lastTick = 0, maxGapUs = 0;
            void tick() {
              final current = watch.elapsedMicroseconds;
              maxGapUs = max(maxGapUs, current - lastTick);
              lastTick = current;
            }

            final probe = Timer.periodic(
              const Duration(milliseconds: 10),
              (_) => tick(),
            );
            late bool written;
            try {
              written = await service.backupNow(
                now: DateTime.utc(2026, 10, 13),
              );
              tick();
            } finally {
              probe.cancel();
              watch.stop();
            }
            final after = ProcessInfo.currentRss;
            await movement;
            final timing = await end();
            final content = jsonDecode(utf8.decode(store.bytes!)) as Map;
            if (!written ||
                content['version'] != 2 ||
                (content['tasks'] as List).length != count) {
              throw StateError('Invalid synthetic backup');
            }
            emit({
              'phase': 'backup_during_scroll',
              'rows': count,
              'sample': sample,
              'duration_us': watch.elapsedMicroseconds,
              'max_event_loop_gap_us': maxGapUs,
              'payload_bytes': store.bytes!.length,
              'rss_before': before,
              'rss_after': after,
              ...timing,
            });
          }
        } finally {
          await db.close();
          await folder.delete(
            recursive: true,
          ); // Only the directory we created.
        }
      }
      emit({'phase': 'complete', 'result': 'PASS'});
    } catch (_) {
      emit({'phase': 'complete', 'result': 'FAIL'});
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(running ? 'Benchmark sintetico' : 'Benchmark terminato'),
    ),
    body: legacy
        ? LegacyAgendaWeekView(
            key: ObjectKey(pages),
            today: date,
            revision: revision,
            controller: pages,
            loadDays: (first, count) async => days(first, count),
            peekDays: (_, _) => null,
            colors: const {},
            onOpenDay: (_) {},
            onOpen: (_) async {},
            now: () => DateTime(2026, 10, 13, 12),
          )
        : AgendaWeekView(
            key: ObjectKey(pages),
            today: date,
            revision: revision,
            controller: pages,
            loadDays: (first, count) async => days(first, count),
            peekDays: (_, _) => null,
            colors: const {},
            onOpenDay: (_) {},
            onOpen: (_) async {},
            now: () => DateTime(2026, 10, 13, 12),
          ),
  );
}

// FrameTiming uses the same monotonic clock as dart:developer Timeline.now.
class _CaptureStore implements EncryptedBackupStore {
  Uint8List? bytes;
  @override
  Future<bool> configured() async => true;
  @override
  Future<List<AutoBackupEntry>> list() async => []; // Force every measured write.
  @override
  Future<void> write(
    String name,
    Uint8List content, {
    required int keep,
  }) async {
    bytes = content;
  }

  @override
  Future<String> setup() => throw UnimplementedError();
  @override
  Future<Uint8List> read(String name) => throw UnimplementedError();
  @override
  Future<Uint8List> decrypt(Uint8List content, {String? code}) =>
      throw UnimplementedError();
}
