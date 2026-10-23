import 'agenda.dart';
import 'task.dart';
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

  /// Semble's API labels the clinic's wall-clock time as UTC: a booking at
  /// 10:00 London in BST comes as `10:00:00.000Z` (Semble's own screen and
  /// the iCal copy show 10:00; checked on 23 October 2026). The digits are
  /// read as Europe/London time and converted to the phone's zone, so a
  /// visit at 10:00 in London shows at 11:00 with the phone in Italy (build
  /// 296). ISO strings with or without `Z`, or epoch milliseconds of the same
  /// digits; an explicit offset other than `Z` is a real instant.
  static DateTime? _instant(Object? value) {
    final epoch = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    if (epoch != null) {
      return londonWallClock(
        DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true),
      ).toLocal();
    }
    if (value is! String || value.trim().isEmpty) return null;
    final text = value.trim();
    if (RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text)) {
      return DateTime.tryParse(text)?.toLocal();
    }
    final digits = DateTime.tryParse(
      '${text.replaceFirst(RegExp('[Zz]\$'), '')}Z',
    );
    return digits == null ? null : londonWallClock(digits).toLocal();
  }
}

/// The instant of Europe/London wall-clock [digits] (given as a UTC
/// DateTime holding the London digits): British Summer Time runs from 01:00
/// UTC on the last Sunday of March to 01:00 UTC on the last Sunday of
/// October. In the skipped spring hour the digits are read as GMT.
DateTime londonWallClock(DateTime digits) {
  final asGmt = DateTime.utc(
    digits.year,
    digits.month,
    digits.day,
    digits.hour,
    digits.minute,
    digits.second,
    digits.millisecond,
  );
  final asBst = asGmt.subtract(const Duration(hours: 1));
  return londonSummerTime(asBst) ? asBst : asGmt;
}

/// London wall-clock digits of [instant], as a UTC DateTime: the inverse
/// of [londonWallClock].
DateTime londonDigitsOf(DateTime instant) {
  final utc = instant.toUtc();
  return londonSummerTime(utc) ? utc.add(const Duration(hours: 1)) : utc;
}

/// A one-day Semble block in London wall clock: date and "HH:mm" times.
typedef SembleBlock = ({CivilDate date, String startTime, String endTime});

/// [start]–[end] (phone time) as a Semble block, or null when the end is
/// not after the start or the block crosses London midnight (Semble's
/// rules are one day long; 24:00 is allowed as the end).
SembleBlock? sembleBlockFor(DateTime start, DateTime end) {
  if (!end.isAfter(start)) return null;
  final from = londonDigitsOf(start);
  final to = londonDigitsOf(end);
  String hm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  final date = CivilDate(from.year, from.month, from.day);
  final sameDay =
      to.year == from.year && to.month == from.month && to.day == from.day;
  final midnight =
      to.hour == 0 &&
      to.minute == 0 &&
      CivilDate(to.year, to.month, to.day) == date.addDays(1);
  if (!sameDay && !midnight) return null;
  return (
    date: date,
    startTime: hm(from),
    endTime: midnight ? '24:00' : hm(to),
  );
}

/// Whether [instant] falls in British Summer Time.
bool londonSummerTime(DateTime instant) {
  final utc = instant.toUtc();
  DateTime switchOn(int month) {
    final last = DateTime.utc(utc.year, month + 1, 0, 1);
    return last.subtract(Duration(days: last.weekday % 7));
  }

  return !utc.isBefore(switchOn(3)) && utc.isBefore(switchOn(10));
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
  List<SembleBooking> at(int minute) => [
    for (final booking in bookings)
      if (_minute(booking.start) == minute &&
          sembleBookingIsMine(booking, surname))
        booking,
  ];
  var candidates = at(_minute(entry.start));
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

/// Clinical minutes written in a Semble visit title: "Follow-up
/// Consultation (15 min)", "Prima visita (adulto) 60'". Semble's slot adds
/// 15 minutes of rest after each visit (checked on 23 October 2026: every
/// `appointment.duration` is the title plus 15). Null when the title has no
/// single duration.
int? sembleTitleMinutes(String title) {
  final found = RegExp(
    r"(\d{1,3})\s*(?:min(?:uti|utes|s)?\b|['’′])",
    caseSensitive: false,
  ).allMatches(title).map((m) => int.parse(m.group(1)!)).toSet();
  return found.length == 1 && found.single > 0 ? found.single : null;
}

/// [entry] ending when its clinical time ends (build 295), so the rest
/// after it shows as such; unchanged when the title gives no shorter time.
AgendaEntry sembleClinicalEntry(AgendaEntry entry) {
  final minutes = sembleTitleMinutes(entry.title);
  if (minutes == null || entry.allDay) return entry;
  final end = entry.start.add(Duration(minutes: minutes));
  if (!end.isBefore(entry.end)) return entry;
  return AgendaEntry(
    instanceId: entry.instanceId,
    calendarIds: entry.calendarIds,
    title: entry.title,
    start: entry.start,
    end: end,
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
}

/// The Calendar entries with Semble's bookings added (build 289): bookings
/// still missing from the phone calendar are added, coloured like the
/// Semble calendar and titled with the appointment type only; any timed event starting in the
/// same minute hides them, and a missing booking is better than a doubled
/// one. Cancelled bookings are never added. Timed events of the Semble
/// calendar and the added bookings end with their clinical time from the
/// title (build 295). Nothing happens without a visible Semble calendar.
List<AgendaEntry> sembleAdjustEntries({
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
  if (semble.isEmpty) return merged;
  final live = <int, SembleBooking>{
    for (final booking in bookings)
      if (!booking.deleted &&
          booking.end != null &&
          booking.end!.isAfter(booking.start))
        _minute(booking.start): booking,
  };
  final taken = {
    for (final entry in merged)
      if (!entry.allDay && !entry.isTask) _minute(entry.start),
  };
  final added = [
    for (final MapEntry(key: minute, value: booking) in live.entries)
      if (!taken.contains(minute))
        sembleClinicalEntry(
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
        ),
  ];
  var trimmed = false;
  final entries = <AgendaEntry>[];
  for (final entry in merged) {
    final clinical = !entry.isTask && entry.calendarIds.any(semble.contains)
        ? sembleClinicalEntry(entry)
        : entry;
    if (!identical(clinical, entry)) trimmed = true;
    entries.add(clinical);
  }
  if (added.isEmpty && !trimmed) return merged;
  return [...entries, ...added]..sort(compareAgendaEntries);
}

int _minute(DateTime value) => value.millisecondsSinceEpoch ~/ 60000;
