import 'task.dart';

/// Semble's clock (build 306: in one place). Semble sends and expects
/// Europe/London wall-clock digits; the app shows phone time. Every
/// conversion goes through this file, tested across both changes of time.

/// The clinic's zone: rules, bookings and blocks are in its wall clock.
const sembleZone = 'Europe/London';

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

/// Minutes to add to Semble's London wall-clock times to draw them on [day]
/// in the phone's zone (build 296): 0 in the UK, 60 in Italy. Measured at
/// London noon, so a change of time at night does not matter.
int sembleZoneShift(CivilDate day) {
  final noon = londonWallClock(DateTime.utc(day.year, day.month, day.day, 12));
  final london = londonSummerTime(noon) ? 60 : 0;
  return noon.toLocal().timeZoneOffset.inMinutes - london;
}
