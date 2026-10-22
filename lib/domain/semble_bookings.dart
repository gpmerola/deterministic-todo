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

  /// ISO 8601 (with Z or an offset) or epoch milliseconds, as local time.
  static DateTime? _instant(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    }
    if (value is! String || value.isEmpty) return null;
    final epoch = int.tryParse(value);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true).toLocal();
    }
    return DateTime.tryParse(value)?.toLocal();
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
}) {
  final minute = _minute(entry.start);
  var candidates = [
    for (final booking in bookings)
      if (_minute(booking.start) == minute &&
          sembleBookingIsMine(booking, surname))
        booking,
  ];
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

/// Semble bookings not yet in the phone calendar (build 289): the iCal
/// export reaches Google and the phone with a delay, the API at once. Shown
/// only while a Semble calendar is visible, coloured like it, and dropped as
/// soon as an event of that calendar starts in the same minute. Cancelled
/// bookings are never added. Titles are the appointment type only.
List<AgendaEntry> sembleDirectEntries({
  required Iterable<SembleBooking> bookings,
  required List<AgendaEntry> merged,
  required List<AgendaCalendar> calendars,
  required Set<String> hiddenCalendarIds,
}) {
  final semble = [
    for (final calendar in calendars)
      if (isSembleCalendar(calendar) &&
          !hiddenCalendarIds.contains(calendar.id))
        calendar.id,
  ];
  if (semble.isEmpty) return const [];
  final taken = {
    for (final entry in merged)
      if (!entry.allDay && entry.calendarIds.any(semble.contains))
        _minute(entry.start),
  };
  final seen = <int>{};
  return [
    for (final booking in bookings)
      if (!booking.deleted &&
          booking.end != null &&
          booking.end!.isAfter(booking.start) &&
          !taken.contains(_minute(booking.start)) &&
          seen.add(_minute(booking.start)))
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
}

int _minute(DateTime value) => value.millisecondsSinceEpoch ~/ 60000;
