import 'dart:math' as math;

import 'task.dart';

/// A calendar the Android system provider exposes (Google, Outlook/Exchange…).
final class AgendaCalendar {
  const AgendaCalendar({
    required this.id,
    required this.name,
    required this.accountName,
    this.colorHex,
    this.visibleBySystem = true,
    this.writable = false,
    this.isGooglePrimary = false,
  });

  final String id;
  final String name;
  final String accountName;
  final String? colorHex;

  /// Whether the phone's calendar app shows it; only the default in Agenda.
  final bool visibleBySystem;

  /// New events can be saved into it (not a subscription or holidays).
  final bool writable;

  /// The Google account's own calendar: the default target, as for exports.
  final bool isGooglePrimary;
}

/// An event typed in Agenda, before it is written to a phone calendar.
final class AgendaEventDraft {
  const AgendaEventDraft({
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.notes,
  });

  final String calendarId;
  final String title;
  final DateTime start;

  /// Exclusive; for all-day drafts the midnight after the last day.
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? notes;

  /// Italian message for the first problem, or null when it can be saved.
  String? get problem {
    if (title.trim().isEmpty) return 'Inserisci un titolo.';
    if (calendarId.isEmpty) return 'Scegli un calendario.';
    if (!end.isAfter(start)) return 'La fine deve essere dopo l\'inizio.';
    return null;
  }
}

/// Calendar preselected for a new event: the last one used if still
/// writable, else the Google primary calendar, else the first writable one.
String? defaultEventCalendar(List<AgendaCalendar> calendars, String? lastUsed) {
  final writable = [
    for (final calendar in calendars)
      if (calendar.writable) calendar,
  ];
  for (final calendar in writable) {
    if (calendar.id == lastUsed) return calendar.id;
  }
  for (final calendar in writable) {
    if (calendar.isGooglePrimary) return calendar.id;
  }
  return writable.firstOrNull?.id;
}

/// Calendars left out of the agenda: an explicit choice wins, otherwise the
/// phone's own visibility setting.
Set<String> hiddenAgendaCalendars(
  List<AgendaCalendar> calendars,
  Map<String, bool> choices,
) => {
  for (final calendar in calendars)
    if (!(choices[calendar.id] ?? calendar.visibleBySystem)) calendar.id,
};

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
    this.unanswered = false,
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

  /// Invitation never accepted or declined (Outlook's dashed events).
  final bool unanswered;
}

/// What the user chose to hide, on top of hidden calendars. Local only.
final class AgendaFilter {
  const AgendaFilter({
    this.hideUnanswered = false,
    this.hiddenWords = const [],
  });

  static const none = AgendaFilter();

  final bool hideUnanswered;

  /// Case-insensitive substrings of the title, e.g. "Live Broadcast".
  final List<String> hiddenWords;

  bool get isActive => hideUnanswered || hiddenWords.isNotEmpty;

  bool hides(AgendaSourceEvent event) {
    if (hideUnanswered && event.unanswered) return true;
    final title = event.title.toLowerCase();
    return hiddenWords.any(
      (word) =>
          word.trim().isNotEmpty && title.contains(word.trim().toLowerCase()),
    );
  }
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
  AgendaFilter filter = AgendaFilter.none,
}) {
  final calendarOrder = {
    for (final (index, calendar) in calendars.indexed) calendar.id: index,
  };
  final visible =
      events
          .where(
            (event) =>
                !event.canceled &&
                !filter.hides(event) &&
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

/// Row from the native `instances` query. `links` holds only meeting URLs
/// extracted from the description on Android.
AgendaSourceEvent agendaEventFromRow(Map<Object?, Object?> row) =>
    AgendaSourceEvent(
      instanceId: row['instanceId']! as String,
      calendarId: row['calendarId']! as String,
      title: row['title'] as String? ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(row['start']! as int),
      end: DateTime.fromMillisecondsSinceEpoch(row['end']! as int),
      allDay: row['allDay'] as bool? ?? false,
      location: row['location'] as String?,
      description: row['links'] as String?,
      canceled: row['canceled'] as bool? ?? false,
      unanswered: row['unanswered'] as bool? ?? false,
    );

/// An entry placed on a one-day timeline, in minutes from local midnight.
final class TimelineBlock {
  const TimelineBlock({
    required this.entry,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final AgendaEntry entry;
  final int startMinute;
  final int endMinute;

  /// Side-by-side slot among overlapping blocks, 0-based, of [columns].
  final int column;
  final int columns;
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

  final result = <TimelineBlock>[];
  var cluster = <({AgendaEntry entry, int start, int end, int column})>[];
  var clusterEnd = -1;
  void flush() {
    final columns = cluster.fold(
      0,
      (max, item) => item.column + 1 > max ? item.column + 1 : max,
    );
    for (final item in cluster) {
      result.add(
        TimelineBlock(
          entry: item.entry,
          startMinute: item.start,
          endMinute: item.end,
          column: item.column,
          columns: columns,
        ),
      );
    }
    cluster = [];
  }

  for (final item in placed) {
    final start = item.start.clamp(0, 24 * 60 - minMinutes);
    final end = math.min(math.max(item.end, start + minMinutes), 24 * 60);
    if (cluster.isNotEmpty && start >= clusterEnd) {
      flush();
      clusterEnd = -1;
    }
    // First column whose blocks have all ended by [start].
    var column = 0;
    while (cluster.any(
      (other) => other.column == column && other.end > start,
    )) {
      column++;
    }
    cluster.add((entry: item.entry, start: start, end: end, column: column));
    clusterEnd = math.max(clusterEnd, end);
  }
  if (cluster.isNotEmpty) flush();
  return result;
}
