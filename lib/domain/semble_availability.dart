import 'agenda.dart';
import 'semble_bookings.dart';
import 'task.dart';

/// Availability rules read from Semble (build 285): when the clinic's
/// practice software shows the clinician as bookable. Read-only and pure:
/// booked appointments still arrive through the Google calendar fed by
/// Semble's iCal export, never from here.
final class SembleRule {
  const SembleRule({
    required this.id,
    required this.unavailability,
    required this.startDate,
    required this.startMinute,
    required this.endMinute,
    this.endDate,
    this.recurrence,
    this.exclusions = const {},
  });

  final String id;

  /// True for a block that removes availability (holiday, admin time…).
  final bool unavailability;

  /// First civil day of the rule; recurring rules may start long before the
  /// range that was asked for.
  final CivilDate startDate;

  /// Last civil day (inclusive), or open-ended when null.
  final CivilDate? endDate;

  /// Clinic wall-clock minutes from midnight, end exclusive.
  final int startMinute;
  final int endMinute;
  final SembleRecurrence? recurrence;

  /// Days on which a recurring rule does not apply.
  final Set<CivilDate> exclusions;

  /// Whether the rule covers [day] (times aside).
  bool appliesOn(CivilDate day) {
    if (day.compareTo(startDate) < 0) return false;
    if (endDate case final last? when day.compareTo(last) > 0) return false;
    if (exclusions.contains(day)) return false;
    final rule = recurrence;
    if (rule == null) {
      // A one-off rule without an end covers its start day only.
      return endDate != null || day == startDate;
    }
    return rule.appliesOn(day, startDate);
  }

  /// Null when a field is missing or in a shape this build does not know:
  /// such a rule is counted and left out rather than guessed.
  static SembleRule? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final unavailability = json['unavailability'];
    final start = _date(json['startDate']);
    final startMinute = _minutes(json['startTime']);
    final endMinute = _minutes(json['endTime']);
    if (id is! String ||
        unavailability is! bool ||
        start == null ||
        startMinute == null ||
        endMinute == null ||
        endMinute <= startMinute) {
      return null;
    }
    final rawEnd = json['endDate'];
    final end = rawEnd == null ? null : _date(rawEnd);
    if (rawEnd != null && end == null) return null;
    SembleRecurrence? recurrence;
    if (json['recurrence'] case final Map<String, Object?> raw) {
      recurrence = SembleRecurrence.fromJson(raw);
      if (recurrence == null) return null;
    }
    final exclusions = <CivilDate>{};
    if (json['exclusions'] case final List<Object?> list) {
      for (final value in list) {
        final date = _date(value);
        if (date != null) exclusions.add(date);
      }
    }
    return SembleRule(
      id: id,
      unavailability: unavailability,
      startDate: start,
      endDate: end,
      startMinute: startMinute,
      endMinute: endMinute,
      recurrence: recurrence,
      exclusions: exclusions,
    );
  }

  /// "2026-10-22" or an ISO timestamp starting with it.
  static CivilDate? _date(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (match == null) return null;
    return CivilDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  /// "10:00", "15:30:00" or "24:00".
  static int? _minutes(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (minute > 59 || hour > 24 || (hour == 24 && minute > 0)) return null;
    return hour * 60 + minute;
  }
}

enum SembleFrequency { daily, weekly }

final class SembleRecurrence {
  const SembleRecurrence({
    required this.frequency,
    this.interval = 1,
    this.daysOfTheWeek = const {},
  });

  final SembleFrequency frequency;
  final int interval;

  /// Semble numbering: 0 = Sunday … 6 = Saturday. Empty for a weekly rule
  /// means the weekday of the start date.
  final Set<int> daysOfTheWeek;

  bool appliesOn(CivilDate day, CivilDate start) {
    final days = day.asLocalDate.difference(start.asLocalDate).inDays;
    switch (frequency) {
      case SembleFrequency.daily:
        return days % interval == 0;
      case SembleFrequency.weekly:
        final weekday = day.asLocalDate.weekday % 7;
        final allowed = daysOfTheWeek.isEmpty
            ? {start.asLocalDate.weekday % 7}
            : daysOfTheWeek;
        if (!allowed.contains(weekday)) return false;
        // Weeks counted from the Monday of the start date.
        final firstMonday = start.addDays(-(start.asLocalDate.weekday - 1));
        final weeks =
            day.asLocalDate.difference(firstMonday.asLocalDate).inDays ~/ 7;
        return weeks % interval == 0;
    }
  }

  static SembleRecurrence? fromJson(Map<String, Object?> json) {
    final frequency = switch (json['frequency']) {
      'daily' => SembleFrequency.daily,
      'weekly' => SembleFrequency.weekly,
      _ => null,
    };
    final interval = json['interval'] ?? 1;
    if (frequency == null || interval is! int || interval < 1) return null;
    final days = <int>{};
    if (json['daysOfTheWeek'] case final List<Object?> list) {
      for (final value in list) {
        final day = value is int ? value : int.tryParse('$value');
        if (day == null || day < 0 || day > 6) return null;
        days.add(day);
      }
    }
    return SembleRecurrence(
      frequency: frequency,
      interval: interval,
      daysOfTheWeek: days,
    );
  }
}

enum SembleBandKind { available, unavailable }

/// A stretch of one civil day drawn behind the events, in minutes from
/// midnight (end exclusive).
final class SembleBand {
  const SembleBand(this.kind, this.startMinute, this.endMinute);

  final SembleBandKind kind;
  final int startMinute;
  final int endMinute;

  @override
  bool operator ==(Object other) =>
      other is SembleBand &&
      other.kind == kind &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(kind, startMinute, endMinute);

  @override
  String toString() => '${kind.name} $startMinute–$endMinute';
}

/// Bands for [day]: availability with unavailability cut out, then every
/// unavailability (also outside availability, so a blocked evening is
/// visible). Sorted by start.
List<SembleBand> sembleBandsFor(Iterable<SembleRule> rules, CivilDate day) {
  final open = <(int, int)>[];
  final closed = <(int, int)>[];
  for (final rule in rules) {
    if (!rule.appliesOn(day)) continue;
    (rule.unavailability ? closed : open).add((
      rule.startMinute,
      rule.endMinute,
    ));
  }
  final blocked = _union(closed);
  final available = [
    for (final span in _union(open)) ..._subtract(span, blocked),
  ];
  return [
    for (final (start, end) in available)
      SembleBand(SembleBandKind.available, start, end),
    for (final (start, end) in blocked)
      SembleBand(SembleBandKind.unavailable, start, end),
  ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
}

/// Minutes to add to Semble's London wall-clock times to draw them on [day]
/// in the phone's zone (build 296): 0 in the UK, 60 in Italy. Measured at
/// London noon, so a change of time at night does not matter.
int sembleZoneShift(CivilDate day) {
  final noon = londonWallClock(DateTime.utc(day.year, day.month, day.day, 12));
  final london = londonSummerTime(noon) ? 60 : 0;
  return noon.toLocal().timeZoneOffset.inMinutes - london;
}

/// [bands] moved by [minutes] and clipped to the day: what goes past
/// midnight is not drawn on the next day.
List<SembleBand> sembleShiftBands(List<SembleBand> bands, int minutes) {
  if (minutes == 0) return bands;
  int clip(int minute) => (minute + minutes).clamp(0, 24 * 60);
  return [
    for (final band in bands)
      if (clip(band.endMinute) > clip(band.startMinute))
        SembleBand(band.kind, clip(band.startMinute), clip(band.endMinute)),
  ];
}

/// Minutes of [day] taken by events (build 287): timed, not tasks, not
/// invitations still unanswered. Clipped to the day, end exclusive.
List<(int, int)> agendaBusyMinutes(
  Iterable<AgendaEntry> entries,
  CivilDate day,
) {
  final dayStart = day.asLocalDate;
  final dayEnd = day.addDays(1).asLocalDate;
  int minuteOf(DateTime value) {
    if (!value.isAfter(dayStart)) return 0;
    if (!value.isBefore(dayEnd)) return 24 * 60;
    return value.hour * 60 + value.minute;
  }

  return [
    for (final entry in entries)
      if (!entry.allDay &&
          !entry.isTask &&
          !entry.unanswered &&
          entry.end.isAfter(dayStart) &&
          entry.start.isBefore(dayEnd))
        (minuteOf(entry.start), minuteOf(entry.end)),
  ].where((span) => span.$2 > span.$1).toList();
}

/// Instance ids of [entries] that are not visits ([isVisit]) and overlap
/// bookable time in [bands] on [day] (build 300): the user wants them
/// highlighted, since they may clash with bookings. With [now], events
/// already over are left out (build 302): nothing to block any more.
Set<String> sembleOverlaps(
  Iterable<AgendaEntry> entries,
  CivilDate day,
  List<SembleBand> bands,
  bool Function(AgendaEntry entry) isVisit, {
  DateTime? now,
}) {
  final open = [
    for (final band in bands)
      if (band.kind == SembleBandKind.available)
        (band.startMinute, band.endMinute),
  ];
  if (open.isEmpty) return const {};
  return {
    for (final entry in entries)
      if (!isVisit(entry) && (now == null || entry.end.isAfter(now)))
        for (final (start, end) in agendaBusyMinutes([entry], day))
          if (open.any((band) => start < band.$2 && end > band.$1))
            entry.instanceId,
  };
}

/// [bands] with [busy] cut out of the available ones: what is still free
/// to book. Unavailable bands stay as they are. A piece left shorter than
/// [minFree] is not bookable (Semble's shortest slot is 30 minutes) and is
/// dropped, so the 15 minutes of rest after a visit are not green (build
/// 295).
List<SembleBand> sembleFreeBands(
  List<SembleBand> bands,
  Iterable<(int, int)> busy, {
  int minFree = 30,
}) {
  final taken = _union(busy.toList());
  if (taken.isEmpty) return bands;
  final result = <SembleBand>[];
  for (final band in bands) {
    if (band.kind != SembleBandKind.available) {
      result.add(band);
      continue;
    }
    for (final (start, end) in _subtract((
      band.startMinute,
      band.endMinute,
    ), taken)) {
      final whole = start == band.startMinute && end == band.endMinute;
      if (whole || end - start >= minFree) {
        result.add(SembleBand(SembleBandKind.available, start, end));
      }
    }
  }
  return result..sort((a, b) => a.startMinute.compareTo(b.startMinute));
}

List<(int, int)> _subtract((int, int) span, List<(int, int)> blocked) {
  final (start, end) = span;
  final out = <(int, int)>[];
  var from = start;
  for (final (blockStart, blockEnd) in blocked) {
    if (blockEnd <= from || blockStart >= end) continue;
    if (blockStart > from) out.add((from, blockStart));
    if (blockEnd > from) from = blockEnd;
  }
  if (from < end) out.add((from, end));
  return out;
}

List<(int, int)> _union(List<(int, int)> spans) {
  final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && span.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, span.$2 > last.$2 ? span.$2 : last.$2));
    } else {
      merged.add(span);
    }
  }
  return merged;
}
