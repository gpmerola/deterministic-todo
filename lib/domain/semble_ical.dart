import 'semble_bookings.dart';

/// The user's Semble iCal link as an https URI (build 312): `webcal://`
/// becomes `https://`; anything else that is not https is refused, so the
/// link never travels in clear.
Uri? sembleIcalUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final https = text.replaceFirst(
    RegExp('^webcals?://', caseSensitive: false),
    'https://',
  );
  final uri = Uri.tryParse(https);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// Bookings in an iCal feed of Semble (build 312), read without the API
/// key: the same feed that fills the Semble calendar in Google. Only start,
/// end, SUMMARY (the visit type, as in the Google copy) and STATUS are
/// kept; DESCRIPTION, LOCATION and attendees are never read. Times with
/// `Z` are instants; with a TZID or floating they are the clinic's
/// Europe/London wall clock. All-day events are not visits. A missing end
/// comes from DURATION, else from the minutes in the title, else 15
/// minutes: a visit with a guessed length beats a missing one. Recurring
/// rules are not expanded (Semble bookings are single). Only events
/// overlapping [from]–[to] are returned, in start order.
List<SembleBooking> parseSembleIcal(
  String text, {
  required DateTime from,
  required DateTime to,
}) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp('\n[ \t]'), '')
      .split('\n');
  final bookings = <SembleBooking>[];
  Map<String, ({String params, String value})>? event;
  for (final line in lines) {
    final upper = line.trim().toUpperCase();
    if (upper == 'BEGIN:VEVENT') {
      event = {};
      continue;
    }
    if (upper == 'END:VEVENT') {
      if (event != null) {
        final booking = _booking(event);
        if (booking != null &&
            booking.end!.isAfter(from) &&
            booking.start.isBefore(to)) {
          bookings.add(booking);
        }
      }
      event = null;
      continue;
    }
    if (event == null) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final head = line.substring(0, colon);
    final semi = head.indexOf(';');
    final name = (semi < 0 ? head : head.substring(0, semi)).toUpperCase();
    // The first occurrence wins, as in a calendar client.
    event.putIfAbsent(
      name,
      () => (
        params: semi < 0 ? '' : head.substring(semi + 1).toUpperCase(),
        value: line.substring(colon + 1).trim(),
      ),
    );
  }
  bookings.sort((a, b) => a.start.compareTo(b.start));
  return bookings;
}

SembleBooking? _booking(Map<String, ({String params, String value})> event) {
  final startProp = event['DTSTART'];
  if (startProp == null || _allDay(startProp)) return null;
  final start = _time(startProp.value);
  if (start == null) return null;
  final title = switch (event['SUMMARY']) {
    final summary? when summary.value.isNotEmpty => _unescape(summary.value),
    _ => null,
  };
  DateTime? end;
  if (event['DTEND'] case final endProp? when !_allDay(endProp)) {
    end = _time(endProp.value);
  }
  if (end == null || !end.isAfter(start)) {
    final minutes =
        _durationMinutes(event['DURATION']?.value) ??
        (title == null ? null : sembleTitleMinutes(title)) ??
        15;
    end = start.add(Duration(minutes: minutes));
  }
  return SembleBooking(
    start: start,
    end: end,
    deleted: event['STATUS']?.value.toUpperCase() == 'CANCELLED',
    appointmentTitle: title,
  );
}

bool _allDay(({String params, String value}) prop) =>
    prop.params.contains('VALUE=DATE') && !prop.params.contains('DATE-TIME') ||
    RegExp(r'^\d{8}$').hasMatch(prop.value);

DateTime? _time(String value) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  final digits = DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6] ?? '0'),
  );
  return (match[7] != null ? digits : londonWallClock(digits)).toLocal();
}

int? _durationMinutes(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  int part(int group) => int.tryParse(match[group] ?? '') ?? 0;
  final minutes = part(1) * 1440 + part(2) * 60 + part(3);
  return minutes > 0 ? minutes : null;
}

String _unescape(String value) => value
    .replaceAll(r'\n', ' ')
    .replaceAll(r'\N', ' ')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\')
    .trim();
