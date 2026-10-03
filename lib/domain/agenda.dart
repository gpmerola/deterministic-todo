import 'task.dart';

/// A calendar the Android system provider exposes (Google, Outlook/Exchange…).
final class AgendaCalendar {
  const AgendaCalendar({
    required this.id,
    required this.name,
    required this.accountName,
    this.colorHex,
  });

  final String id;
  final String name;
  final String accountName;
  final String? colorHex;
}

/// One occurrence read from the system provider. Never persisted or synced:
/// work calendars may contain clinical details.
final class AgendaSourceEvent {
  const AgendaSourceEvent({
    required this.instanceId,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.description,
    this.url,
    this.canceled = false,
  });

  final String instanceId;
  final String calendarId;
  final String title;
  final DateTime start;

  /// Exclusive. All-day events use local midnights.
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;
  final String? url;
  final bool canceled;
}

/// An entry shown once even when the same meeting is in several calendars.
final class AgendaEntry {
  const AgendaEntry({
    required this.instanceId,
    required this.calendarIds,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.meeting,
  });

  final String instanceId;

  /// First is the calendar used for colour; the rest are duplicates merged in.
  final List<String> calendarIds;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final MeetingLink? meeting;
}

final class AgendaDay {
  const AgendaDay(this.date, this.entries);
  final CivilDate date;
  final List<AgendaEntry> entries;
}

final class MeetingLink {
  const MeetingLink(this.provider, this.url);
  final String provider;
  final Uri url;
}

final _meetingPatterns = <(String, RegExp)>[
  ('Teams', RegExp(r'https://teams\.microsoft\.com/l/meetup-join/[^\s<>"]+')),
  ('Teams', RegExp(r'https://teams\.microsoft\.com/meet/[^\s<>"]+')),
  ('Teams', RegExp(r'https://teams\.live\.com/meet/[^\s<>"]+')),
  ('Zoom', RegExp(r'https://[\w.-]*zoom\.us/j/[^\s<>"]+')),
  ('Meet', RegExp(r'https://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+')),
];

/// First online-meeting link in url, then location, then description.
MeetingLink? findMeetingLink(AgendaSourceEvent event) {
  for (final text in [event.url, event.location, event.description]) {
    if (text == null || text.isEmpty) continue;
    for (final (provider, pattern) in _meetingPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      // Outlook wraps links in <…> or ends them with punctuation.
      final raw = match.group(0)!.replaceFirst(RegExp(r'[>)\].,;]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri != null) return MeetingLink(provider, uri);
    }
  }
  return null;
}

/// Groups visible, non-cancelled events into [days] civil days from [first].
///
/// The same meeting in two calendars (same title, start, end and all-day flag)
/// is shown once; the order of [calendars] decides which one gives the colour.
List<AgendaDay> buildAgenda({
  required List<AgendaSourceEvent> events,
  required List<AgendaCalendar> calendars,
  required Set<String> hiddenCalendarIds,
  required CivilDate first,
  required int days,
}) {
  final calendarOrder = {
    for (final (index, calendar) in calendars.indexed) calendar.id: index,
  };
  final visible =
      events
          .where(
            (event) =>
                !event.canceled &&
                calendarOrder.containsKey(event.calendarId) &&
                !hiddenCalendarIds.contains(event.calendarId),
          )
          .toList()
        ..sort((a, b) {
          final byCalendar = calendarOrder[a.calendarId]!.compareTo(
            calendarOrder[b.calendarId]!,
          );
          return byCalendar != 0
              ? byCalendar
              : a.instanceId.compareTo(b.instanceId);
        });

  final merged = <String, _MutableEntry>{};
  for (final event in visible) {
    final key = [
      event.title.trim().toLowerCase(),
      event.start.millisecondsSinceEpoch,
      event.end.millisecondsSinceEpoch,
      event.allDay,
    ].join('|');
    final existing = merged[key];
    if (existing == null) {
      merged[key] = _MutableEntry(event);
    } else if (!existing.calendarIds.contains(event.calendarId)) {
      existing.calendarIds.add(event.calendarId);
      existing.meeting ??= findMeetingLink(event);
    }
  }

  final entries = merged.values.map((value) => value.freeze()).toList()
    ..sort(_compareEntries);
  return [
    for (var index = 0; index < days; index++)
      _day(first.addDays(index), entries),
  ];
}

AgendaDay _day(CivilDate date, List<AgendaEntry> entries) {
  final dayStart = date.asLocalDate;
  final dayEnd = date.addDays(1).asLocalDate;
  return AgendaDay(date, [
    for (final entry in entries)
      if (_overlaps(entry, dayStart, dayEnd)) entry,
  ]);
}

bool _overlaps(AgendaEntry entry, DateTime dayStart, DateTime dayEnd) {
  // A zero-length event still belongs to the day it starts on.
  final end = entry.end.isAfter(entry.start)
      ? entry.end
      : entry.start.add(const Duration(milliseconds: 1));
  return entry.start.isBefore(dayEnd) && end.isAfter(dayStart);
}

int _compareEntries(AgendaEntry a, AgendaEntry b) {
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  for (final result in [
    a.start.compareTo(b.start),
    a.end.compareTo(b.end),
    a.title.compareTo(b.title),
    a.instanceId.compareTo(b.instanceId),
  ]) {
    if (result != 0) return result;
  }
  return 0;
}

final class _MutableEntry {
  _MutableEntry(this.source)
    : calendarIds = [source.calendarId],
      meeting = findMeetingLink(source);

  final AgendaSourceEvent source;
  final List<String> calendarIds;
  MeetingLink? meeting;

  AgendaEntry freeze() => AgendaEntry(
    instanceId: source.instanceId,
    calendarIds: List.unmodifiable(calendarIds),
    title: source.title,
    start: source.start,
    end: source.end,
    allDay: source.allDay,
    location: source.location,
    meeting: meeting,
  );
}
