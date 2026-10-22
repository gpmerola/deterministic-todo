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

int _minute(DateTime value) => value.millisecondsSinceEpoch ~/ 60000;
