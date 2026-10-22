import 'agenda.dart';
import 'semble_bookings.dart';
import 'text_fold.dart';

/// OPUK schedule, September 2026. Pounds are represented as integer pence.
enum PrivateFee {
  initial('Prima visita · 60 min', 17000),
  childInitial('Prima visita C&A · 90 min', 20000),
  followUp15('Follow-up · 15 min', 6500),
  followUp30('Follow-up · 30 min', 11000),
  prescription('Repeat prescription', 1000),
  letter('Report / lettera', 4500),
  adhdAssessment('ADHD · valutazione', 21500),
  adhdFeedback('ADHD · feedback', 8500);

  const PrivateFee(this.label, this.pence);
  final String label;
  final int pence;
}

bool isPrivateWorkCalendar(AgendaCalendar calendar) => RegExp(
  r'\b(opuk|semble|heydoc)\b|online psychiatry',
  caseSensitive: false,
).hasMatch('${calendar.name} ${calendar.accountName}');

/// Only explicit service labels are priced. A person's name or duration alone
/// is never enough. ASD has no final agreed fee and is deliberately unpriced.
PrivateFee? privateFeeFor(AgendaEntry entry) {
  final title = foldForSearch(entry.title);
  bool has(String pattern) => RegExp(pattern).hasMatch(title);
  final slotMinutes = entry.end.difference(entry.start).inSeconds / 60;
  final durations = RegExp(
    r'\b(\d{1,3})\s*(?:minutes|minuti|mins|min)\b',
  ).allMatches(title).map((m) => int.parse(m.group(1)!)).toSet();
  if (durations.length > 1) return null;
  // Booking systems can append administration time to the calendar slot.
  // Use an explicit service duration only if it fits inside that slot.
  final minutes = durations.isEmpty ? slotMinutes : durations.single;
  if (minutes <= 0 || minutes > slotMinutes) return null;
  final child = has(
    r'\bc\s*&\s*a\b|\b(child|adolescent|children|adolescenti|bambini|minori)\b',
  );
  if (has(r'\b(asd|autism|autismo)\b')) return null;
  if (has(r'\badhd\b')) {
    // Follow-ups use the ordinary schedule; reports/admin are already included
    // in the assessment package, so never charge them for a second time.
    if (has(r'\bfollow[\s‐‑–-]?up\b')) {
      return switch (minutes) {
        15 => PrivateFee.followUp15,
        30 => PrivateFee.followUp30,
        _ => null,
      };
    }
    // The available assessment package is explicitly for adults only.
    if (child) return null;
    if (has(r'\b(report|reports|letter|letters|admin)\b')) return null;
    if (has(r'\bfeedback\b')) return PrivateFee.adhdFeedback;
    if (has(r'\b(assessment|valutazione)\b')) {
      return PrivateFee.adhdAssessment;
    }
    return null;
  }
  if (has(r'\brepeat prescription\b|\brinnovo ricetta\b')) {
    return PrivateFee.prescription;
  }
  if (has(r'\b(report|reports|letter|letters|lettera|relazione)\b')) {
    return PrivateFee.letter;
  }
  if (has(r'\bfollow[\s‐‑–-]?up\b|\bcontrollo\b')) {
    return switch (minutes) {
      15 => PrivateFee.followUp15,
      30 => PrivateFee.followUp30,
      _ => null,
    };
  }
  if (has(r'\b(prima visita|initial|first|new patient)\b')) {
    if (minutes == 60) return PrivateFee.initial;
    if (minutes == 90 && child) {
      return PrivateFee.childInitial;
    }
  }
  return null;
}

class PrivateEarnings {
  const PrivateEarnings({
    required this.asOf,
    required this.counts,
    required this.unpriced,
    required this.scheduledCounts,
    required this.scheduledUnpriced,
    this.dnaCounts = const {},
    this.dnaUnpriced = 0,
    this.sembleCancelled = 0,
    this.sembleMatched,
    this.sembleProblem,
    this.sembleVisits,
  });
  final DateTime asOf;
  final Map<PrivateFee, int> counts;
  final int unpriced;

  /// Appointments not yet ended, including those currently in progress.
  final Map<PrivateFee, int> scheduledCounts;
  final int scheduledUnpriced;

  /// Visits Semble marked "did not attend" (build 288): left out of both
  /// totals and shown apart.
  final Map<PrivateFee, int> dnaCounts;
  final int dnaUnpriced;

  /// Visits whose Semble booking was deleted while the calendar kept them.
  final int sembleCancelled;

  /// Calendar visits for which Semble gave an outcome; null when Semble was
  /// not read (no key, offline, other zone).
  final ({int matched, int checked})? sembleMatched;

  /// Why Semble outcomes are missing, for the sheet; null when read or not
  /// configured.
  final String? sembleProblem;

  /// Semble visits of the month taken from the bookings themselves (build
  /// 293), not from the calendar; null when the calendar was used.
  final int? sembleVisits;

  PrivateEarnings withSembleProblem(String problem) =>
      _copy(sembleProblem: problem);

  PrivateEarnings withSembleVisits(int visits) => _copy(sembleVisits: visits);

  PrivateEarnings _copy({String? sembleProblem, int? sembleVisits}) =>
      PrivateEarnings(
        asOf: asOf,
        counts: counts,
        unpriced: unpriced,
        scheduledCounts: scheduledCounts,
        scheduledUnpriced: scheduledUnpriced,
        dnaCounts: dnaCounts,
        dnaUnpriced: dnaUnpriced,
        sembleCancelled: sembleCancelled,
        sembleMatched: sembleMatched,
        sembleProblem: sembleProblem ?? this.sembleProblem,
        sembleVisits: sembleVisits ?? this.sembleVisits,
      );
  int get dnaPence =>
      dnaCounts.entries.fold(0, (sum, e) => sum + e.key.pence * e.value);
  int get dnaVisits =>
      dnaCounts.values.fold(0, (sum, n) => sum + n) + dnaUnpriced;
  int get pence =>
      counts.entries.fold(0, (sum, e) => sum + e.key.pence * e.value);
  int get visits => counts.values.fold(0, (sum, n) => sum + n);
  int get scheduledPence =>
      scheduledCounts.entries.fold(0, (sum, e) => sum + e.key.pence * e.value);
  int get scheduledVisits =>
      scheduledCounts.values.fold(0, (sum, n) => sum + n);
  int get monthPence => pence + scheduledPence;
}

/// [outcome] gives Semble's record for an entry when bookings were read;
/// [sembleEntry] says which entries come from the Semble calendar.
PrivateEarnings estimatePrivateEarnings(
  Iterable<AgendaEntry> entries,
  DateTime now, {
  SembleOutcome Function(AgendaEntry entry)? outcome,
  bool Function(AgendaEntry entry)? sembleEntry,
}) {
  final start = DateTime(now.year, now.month);
  final until = DateTime(now.year, now.month + 1);
  final seen = <String>{};
  final counts = <PrivateFee, int>{};
  final scheduledCounts = <PrivateFee, int>{};
  final dnaCounts = <PrivateFee, int>{};
  var unpriced = 0;
  var scheduledUnpriced = 0;
  var dnaUnpriced = 0;
  var sembleCancelled = 0;
  var checked = 0;
  var matched = 0;
  for (final entry in entries) {
    if (entry.isTask ||
        entry.allDay ||
        entry.unanswered ||
        entry.start.isBefore(start) ||
        !entry.start.isBefore(until) ||
        !entry.end.isAfter(entry.start) ||
        isCanceledTitle(entry.title)) {
      continue;
    }
    final title = foldForSearch(entry.title);
    if (RegExp(
      r'\b(cancelled|canceled|annullat[oa]|no[ -]?show|dna)\b',
    ).hasMatch(title)) {
      continue;
    }
    final key = '${entry.instanceId}|${entry.start.millisecondsSinceEpoch}';
    if (!seen.add(key)) continue;
    final fee = privateFeeFor(entry);
    if (outcome != null && (sembleEntry?.call(entry) ?? true)) {
      checked++;
      final recorded = outcome(entry);
      if (recorded != SembleOutcome.unknown) matched++;
      if (recorded == SembleOutcome.cancelled) {
        sembleCancelled++;
        continue;
      }
      if (recorded == SembleOutcome.dna) {
        if (fee == null) {
          dnaUnpriced++;
        } else {
          dnaCounts.update(fee, (n) => n + 1, ifAbsent: () => 1);
        }
        continue;
      }
    }
    final scheduled = entry.end.isAfter(now);
    if (fee == null) {
      if (scheduled) {
        scheduledUnpriced++;
      } else {
        unpriced++;
      }
    } else {
      (scheduled ? scheduledCounts : counts).update(
        fee,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
  }
  return PrivateEarnings(
    asOf: now,
    counts: Map.unmodifiable(counts),
    unpriced: unpriced,
    scheduledCounts: Map.unmodifiable(scheduledCounts),
    scheduledUnpriced: scheduledUnpriced,
    dnaCounts: Map.unmodifiable(dnaCounts),
    dnaUnpriced: dnaUnpriced,
    sembleCancelled: sembleCancelled,
    sembleMatched: outcome == null
        ? null
        : (matched: matched, checked: checked),
  );
}

/// The month's private work with Semble's bookings as the source of its
/// visits (build 293): type, times and outcome come from each booking, so
/// the estimate no longer depends on the iCal copy, its titles or its wrong
/// summer times. Calendar entries of a Semble calendar are dropped, and so
/// is any other private calendar entry starting with a booking (also one UTC
/// offset early, like the iCal copy). heydoc and other visits stay. A
/// deleted booking counts as cancelled only when no live booking of the user
/// starts in the same minute (moved in place).
PrivateEarnings estimateWithSembleBookings({
  required Iterable<AgendaEntry> calendarEntries,
  required Iterable<SembleBooking> bookings,
  required Set<String> sembleCalendarIds,
  required DateTime now,
  Duration Function(DateTime) offsetOf = deviceOffset,
}) {
  int minute(DateTime value) => value.millisecondsSinceEpoch ~/ 60000;
  final all = bookings.toList();
  final booked = {for (final booking in all) minute(booking.start)};
  final live = {
    for (final booking in all)
      if (!booking.deleted) minute(booking.start),
  };
  final outcomes = <String, SembleOutcome>{};
  final visits = <AgendaEntry>[];
  for (final (index, booking) in all.indexed) {
    if (booking.deleted && live.contains(minute(booking.start))) continue;
    final id =
        '$sembleBookingPrefix${booking.start.millisecondsSinceEpoch}#$index';
    outcomes[id] = booking.outcome;
    visits.add(
      AgendaEntry(
        instanceId: id,
        calendarIds: const ['semble'],
        title: booking.appointmentTitle ?? '',
        start: booking.start,
        end: booking.end ?? booking.start,
        allDay: false,
      ),
    );
  }
  final others = [
    for (final entry in calendarEntries)
      if (!entry.calendarIds.any(sembleCalendarIds.contains) &&
          !booked.contains(minute(entry.start)) &&
          !booked.contains(minute(entry.start.add(offsetOf(entry.start)))))
        entry,
  ];
  final result = estimatePrivateEarnings(
    [...others, ...visits],
    now,
    outcome: (entry) => outcomes[entry.instanceId] ?? SembleOutcome.unknown,
    sembleEntry: (entry) => outcomes.containsKey(entry.instanceId),
  );
  final month = visits
      .where(
        (visit) =>
            !visit.start.isBefore(DateTime(now.year, now.month)) &&
            visit.start.isBefore(DateTime(now.year, now.month + 1)),
      )
      .length;
  return result.withSembleVisits(month);
}
