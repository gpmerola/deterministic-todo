/// One-day timeline layout: blocks, scale and overlap columns.
library;

import 'dart:math' as math;

import 'agenda.dart';
import 'task.dart';

/// An entry placed on a one-day timeline, in minutes from local midnight.
final class TimelineBlock {
  const TimelineBlock({
    required this.entry,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
    this.indent = 0,
  });

  final AgendaEntry entry;
  final int startMinute;
  final int endMinute;

  /// Side-by-side slot among events starting together, 0-based, of
  /// [columns].
  final int column;
  final int columns;

  /// Cascade level: an event starting well after one it overlaps is drawn
  /// over it, shifted right by this many steps, instead of squeezing both
  /// into narrow columns (Google Calendar's layout, build 220).
  final int indent;
}

/// "ora" while [start]–[end] is under way, "tra 25 min" within the next
/// hour, otherwise null: how soon the next appointment is (build 221).
String? relativeStartLabel(DateTime start, DateTime end, DateTime now) {
  if (!now.isBefore(start) && now.isBefore(end)) return 'ora';
  final minutes = (start.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0 || minutes > 60) return null;
  return minutes == 60 ? 'tra 1 ora' : 'tra $minutes min';
}

/// Event span picked by press-and-drag on a timeline: from the quarter
/// hour pressed to the quarter hour reached, at least 15 minutes, either
/// direction, inside the day (build 221).
({int start, int end}) dragSpan(int pressedMinute, int currentMinute) {
  int snap(int minute) => ((minute / 15).round() * 15).clamp(0, 24 * 60);
  final a = snap(pressedMinute).clamp(0, 24 * 60 - 15);
  final b = snap(currentMinute);
  if (b >= a + 15) return (start: a, end: b);
  if (b <= a - 15) return (start: b, end: a);
  return (start: a, end: a + 15);
}

/// Vertical scale of a day timeline: full height for the useful hours
/// (by default 7:00–21:00, widened to every event of [blocks]), a narrow
/// band for the others, so empty nights do not push the day off screen
/// (build 221). Minutes map to offsets and back for taps and drags.
final class TimelineScale {
  TimelineScale._(this.hourHeights) : _tops = _offsets(hourHeights);

  static List<double> _offsets(List<double> heights) {
    final tops = [0.0];
    for (final height in heights) {
      tops.add(tops.last + height);
    }
    return tops;
  }

  factory TimelineScale.forBlocks(
    Iterable<TimelineBlock> blocks, {
    required double hourHeight,
    double foldedHeight = 14,
    int firstHour = 7,
    int lastHour = 21,
  }) {
    var first = firstHour;
    var last = lastHour;
    for (final block in blocks) {
      first = math.min(first, block.startMinute ~/ 60);
      last = math.max(last, (block.endMinute + 59) ~/ 60);
    }
    return TimelineScale._([
      for (var hour = 0; hour < 24; hour++)
        hour >= first && hour < last ? hourHeight : foldedHeight,
    ]);
  }

  /// Height of each hour, 0–23.
  final List<double> hourHeights;
  final List<double> _tops;

  double get total => _tops[24];

  bool isFolded(int hour) => hourHeights[hour] < hourHeights.reduce(math.max);

  /// Offset of [minute] (0–1440) from midnight.
  double y(int minute) {
    final clamped = minute.clamp(0, 24 * 60);
    final hour = math.min(clamped ~/ 60, 23);
    return _tops[hour] + (clamped - hour * 60) / 60 * hourHeights[hour];
  }

  /// Minute at offset [dy], the inverse of [y].
  int minuteAt(double dy) {
    if (dy <= 0) return 0;
    for (var hour = 0; hour < 24; hour++) {
      if (dy < _tops[hour + 1]) {
        return hour * 60 +
            ((dy - _tops[hour]) / hourHeights[hour] * 60).floor();
      }
    }
    return 24 * 60;
  }
}

/// Horizontal placement of [block] in a lane [width] wide: left offset and
/// width. Each cascade step shifts right by 12% of the lane (at most four
/// steps); columns share what is left.
({double left, double width}) timelineSlot(TimelineBlock block, double width) {
  final step = width * 0.12;
  final shift = math.min(block.indent, 4) * step;
  final columnWidth = (width - shift) / block.columns;
  return (left: shift + block.column * columnWidth, width: columnWidth);
}

/// Timed events that overlap another timed event, by instance id, with the
/// events they clash with in start order. All-day events and Todo tasks
/// never clash; touching events (one ends when the next starts) do not.
/// Duplicates were already merged, so the same meeting in two calendars is
/// not a clash.
Map<String, List<AgendaEntry>> agendaOverlaps(Iterable<AgendaEntry> entries) {
  final timed =
      entries
          .where((e) => !e.allDay && !e.isTask && e.end.isAfter(e.start))
          .toList()
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.instanceId.compareTo(b.instanceId);
        });
  final result = <String, List<AgendaEntry>>{};
  final active = <AgendaEntry>[];
  for (final entry in timed) {
    active.removeWhere((other) => !other.end.isAfter(entry.start));
    for (final other in active) {
      (result[other.instanceId] ??= []).add(entry);
      (result[entry.instanceId] ??= []).add(other);
    }
    active.add(entry);
  }
  for (final clashes in result.values) {
    clashes.sort((a, b) => a.start.compareTo(b.start));
  }
  return result;
}

/// Lays out the timed entries of [day] like a calendar day view: clipped to
/// the day, at least [minMinutes] tall, overlapping ones in side-by-side
/// columns. All-day entries are left to the caller.
List<TimelineBlock> layoutDayTimeline(
  List<AgendaEntry> entries,
  CivilDate day, {
  int minMinutes = 20,
}) {
  final dayStart = day.asLocalDate;
  final dayEnd = day.addDays(1).asLocalDate;
  // Wall-clock minutes, so a DST day still maps 00:00–24:00 to the grid.
  int minuteOf(DateTime moment) {
    if (!moment.isAfter(dayStart)) return 0;
    if (!moment.isBefore(dayEnd)) return 24 * 60;
    return moment.hour * 60 + moment.minute;
  }

  final placed =
      [
        for (final entry in entries)
          if (!entry.allDay)
            (
              entry: entry,
              start: minuteOf(entry.start),
              end: minuteOf(entry.end),
            ),
      ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : b.end.compareTo(a.end);
      });

  // Events starting within this window of each other share columns;
  // later overlapping ones cascade over them (see [TimelineBlock.indent]).
  const parallelWindow = 30;
  final groups = <_TimelineGroup>[];
  for (final item in placed) {
    final start = item.start.clamp(0, 24 * 60 - minMinutes);
    final end = math.min(math.max(item.end, start + minMinutes), 24 * 60);
    final active = [
      for (final group in groups)
        if (group.end > start) group,
    ];
    final parallel = active
        .where((group) => group.start + parallelWindow > start)
        .lastOrNull;
    final group =
        parallel ??
        _TimelineGroup(
          start,
          active.isEmpty ? 0 : active.map((g) => g.indent).reduce(math.max) + 1,
        );
    if (parallel == null) groups.add(group);
    // First column whose blocks have all ended by [start].
    var column = 0;
    while (group.items.any(
      (other) => other.column == column && other.end > start,
    )) {
      column++;
    }
    group.items.add((
      entry: item.entry,
      start: start,
      end: end,
      column: column,
    ));
    group.end = math.max(group.end, end);
  }
  final result = <TimelineBlock>[];
  for (final group in groups) {
    final columns = group.items.fold(
      0,
      (max, item) => item.column + 1 > max ? item.column + 1 : max,
    );
    for (final item in group.items) {
      result.add(
        TimelineBlock(
          entry: item.entry,
          startMinute: item.start,
          endMinute: item.end,
          column: item.column,
          columns: columns,
          indent: group.indent,
        ),
      );
    }
  }
  return result;
}

final class _TimelineGroup {
  _TimelineGroup(this.start, this.indent) : end = start;
  final int start;
  final int indent;
  int end;
  final items = <({AgendaEntry entry, int start, int end, int column})>[];
}
