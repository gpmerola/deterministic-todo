import 'agenda.dart';
import 'text_fold.dart';

/// What Semble recorded for a booking (build 288). Read from
/// `bookingJourney`: Semble has no status enum for attendance, only the
/// moments the reception marks.
enum SembleOutcome { attended, dna, cancelled, unknown }

/// A clinic booking without any patient field: start, length, type and
/// journey. The key cannot read the clinician (`settingsSeeUsers`), so
/// [doctorName] is set only when Semble returns it.
final class SembleBooking {
  const SembleBooking({
    required this.start,
    required this.deleted,
    this.end,
    this.appointmentTitle,
    this.doctorName,
    this.arrived = false,
    this.dna = false,
  });

  final DateTime start;
  final DateTime? end;
  final bool deleted;
  final String? appointmentTitle;
  final String? doctorName;

  /// Arrival, consultation or departure was marked.
  final bool arrived;

  /// "Did not attend" was marked.
  final bool dna;

  SembleOutcome get outcome {
    if (deleted) return SembleOutcome.cancelled;
    if (dna) return SembleOutcome.dna;
    if (arrived) return SembleOutcome.attended;
    return SembleOutcome.unknown;
  }

  static SembleBooking? fromJson(Map<String, Object?> json) {
    final start = _instant(json['start']);
    if (start == null) return null;
    final journey = json['bookingJourney'];
    bool marked(String field) =>
        journey is Map<String, Object?> && _instant(journey[field]) != null;
    final appointment = json['appointment'];
    return SembleBooking(
      start: start,
      end: _instant(json['end']),
      deleted: json['deleted'] == true,
      appointmentTitle: appointment is Map<String, Object?>
          ? appointment['title'] as String?
          : null,
      doctorName: json['doctorName'] as String?,
      arrived:
          marked('arrived') || marked('consultation') || marked('departed'),
      dna: marked('dna'),
    );
  }

  /// ISO 8601 or epoch milliseconds, as local time. Semble sends booking
  /// times in UTC, sometimes without the `Z`: a string with no offset is
  /// read as UTC, not as device time (build 291, copies an hour early).
  static DateTime? _instant(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    }
    if (value is! String || value.isEmpty) return null;
    final epoch = int.tryParse(value);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true).toLocal();
    }
    final zoned = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$', caseSensitive: false);
    final text = value.trim();
    final hasTime = text.contains(RegExp('[T ]'));
    return DateTime.tryParse(
      hasTime && !zoned.hasMatch(text) ? '${text}Z' : text,
    )?.toLocal();
  }
}

/// Whether [booking] belongs to the clinician named [surname], when Semble
/// gave a name; true when it did not (matching then relies on time and type).
bool sembleBookingIsMine(SembleBooking booking, String? surname) {
  final name = booking.doctorName;
  if (surname == null || name == null) return true;
  return foldForSearch(name).contains(foldForSearch(surname));
}

/// The outcome Semble recorded for the calendar [entry]: the booking that
/// starts at the same minute, narrowed by appointment type when several
/// clinicians start together. [SembleOutcome.unknown] when nothing or
/// several disagreeing bookings match: never guessed.
SembleOutcome sembleOutcomeFor(
  AgendaEntry entry,
  Iterable<SembleBooking> bookings, {
  String? surname,
  Duration Function(DateTime) offsetOf = deviceOffset,
}) {
  List<SembleBooking> at(int minute) => [
    for (final booking in bookings)
      if (_minute(booking.start) == minute &&
          sembleBookingIsMine(booking, surname))
        booking,
  ];
  var candidates = at(_minute(entry.start));
  // The iCal copy may show UTC digits as local time (seen in BST, build 292).
  final offset = offsetOf(entry.start);
  if (candidates.isEmpty && offset != Duration.zero) {
    candidates = at(_minute(entry.start.add(offset)));
  }
  if (candidates.length > 1) {
    final title = foldForSearch(entry.title);
    final typed = [
      for (final booking in candidates)
        if (booking.appointmentTitle case final type?
            when type.trim().isNotEmpty &&
                title.contains(foldForSearch(type).trim()))
          booking,
    ];
    if (typed.isNotEmpty) candidates = typed;
  }
  // A cancelled booking and its live replacement can share the start.
  final live = [
    for (final booking in candidates)
      if (!booking.deleted) booking,
  ];
  if (live.isNotEmpty) candidates = live;
  final outcomes = {for (final booking in candidates) booking.outcome};
  return outcomes.length == 1 ? outcomes.single : SembleOutcome.unknown;
}

/// The calendar fed by Semble's iCal export.
bool isSembleCalendar(AgendaCalendar calendar) => RegExp(
  r'\bsemble\b',
  caseSensitive: false,
).hasMatch('${calendar.name} ${calendar.accountName}');

/// Prefix of [AgendaEntry.instanceId] for bookings read straight from
/// Semble (build 289).
const sembleBookingPrefix = 'semble-booking:';

extension SembleBookingEntry on AgendaEntry {
  bool get isSembleBooking => instanceId.startsWith(sembleBookingPrefix);
}

/// The device's UTC offset at [moment]. Semble's iCal export writes UTC
/// wall-clock digits as local time, so in British Summer Time every copy is
/// an hour early (seen on 22 October 2026): adding this offset gives the
/// instant it meant. Tests pass another zone.
Duration deviceOffset(DateTime moment) => moment.toLocal().timeZoneOffset;

/// The Calendar entries with Semble's bookings applied (builds 289–292):
///
/// An event of a visible Semble calendar that starts exactly one UTC offset
/// before a live booking is the iCal copy written in UTC digits: it is drawn
/// at the booking's time, keeping its title and id. Bookings still missing
/// from the phone calendar are added, coloured like the Semble calendar and
/// titled with the appointment type only; any timed event starting in the
/// same minute hides them, and a missing booking is better than a doubled
/// one. Cancelled bookings are never added. Nothing happens without a
/// visible Semble calendar.
List<AgendaEntry> sembleAdjustEntries({
  required Iterable<SembleBooking> bookings,
  required List<AgendaEntry> merged,
  required List<AgendaCalendar> calendars,
  required Set<String> hiddenCalendarIds,
  Duration Function(DateTime) offsetOf = deviceOffset,
}) {
  final semble = [
    for (final calendar in calendars)
      if (isSembleCalendar(calendar) &&
          !hiddenCalendarIds.contains(calendar.id))
        calendar.id,
  ];
  if (semble.isEmpty) return merged;
  final live = <int, SembleBooking>{
    for (final booking in bookings)
      if (!booking.deleted &&
          booking.end != null &&
          booking.end!.isAfter(booking.start))
        _minute(booking.start): booking,
  };
  final exact = {
    for (final entry in merged)
      if (!entry.allDay && entry.calendarIds.any(semble.contains))
        _minute(entry.start),
  };
  var moved = false;
  final entries = <AgendaEntry>[];
  for (final entry in merged) {
    final offset = offsetOf(entry.start);
    final meant = _minute(entry.start.add(offset));
    final early =
        !entry.allDay &&
        offset != Duration.zero &&
        entry.calendarIds.any(semble.contains) &&
        !live.containsKey(_minute(entry.start)) &&
        live.containsKey(meant) &&
        !exact.contains(meant);
    if (early) moved = true;
    entries.add(early ? _shifted(entry, offset) : entry);
  }
  final taken = {
    for (final entry in entries)
      if (!entry.allDay && !entry.isTask) _minute(entry.start),
  };
  final added = [
    for (final MapEntry(key: minute, value: booking) in live.entries)
      if (!taken.contains(minute))
        AgendaEntry(
          instanceId:
              '$sembleBookingPrefix${booking.start.millisecondsSinceEpoch}',
          calendarIds: [semble.first],
          title: switch (booking.appointmentTitle?.trim()) {
            final type? when type.isNotEmpty => type,
            _ => 'Prenotazione Semble',
          },
          start: booking.start,
          end: booking.end!,
          allDay: false,
          isOrganizer: false,
        ),
  ];
  if (!moved && added.isEmpty) return merged;
  return [...entries, ...added]..sort(compareAgendaEntries);
}

AgendaEntry _shifted(AgendaEntry entry, Duration by) => AgendaEntry(
  instanceId: entry.instanceId,
  calendarIds: entry.calendarIds,
  title: entry.title,
  start: entry.start.add(by),
  end: entry.end.add(by),
  allDay: entry.allDay,
  location: entry.location,
  meeting: entry.meeting,
  timeZone: entry.timeZone,
  eventZoneTimes: entry.eventZoneTimes,
  isOrganizer: entry.isOrganizer,
  changedOccurrence: entry.changedOccurrence,
  taskId: entry.taskId,
  completed: entry.completed,
  unanswered: entry.unanswered,
  key: entry.key,
);

int _minute(DateTime value) => value.millisecondsSinceEpoch ~/ 60000;
