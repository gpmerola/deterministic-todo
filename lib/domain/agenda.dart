import 'dart:math' as math;

import 'task.dart';
import 'text_fold.dart';

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

/// Repetition offered when creating an event, like Google Calendar's menu.
enum AgendaRepeat { none, daily, weekdays, weekly, monthly, yearly }

/// Italian label for [repeat], anchored on the event's [start] day.
String agendaRepeatLabel(AgendaRepeat repeat, DateTime start) {
  const weekdays = [
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato',
    'domenica',
  ];
  const months = [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];
  return switch (repeat) {
    AgendaRepeat.none => 'Non si ripete',
    AgendaRepeat.daily => 'Ogni giorno',
    AgendaRepeat.weekdays => 'Giorni feriali (lun–ven)',
    AgendaRepeat.weekly => 'Ogni settimana di ${weekdays[start.weekday - 1]}',
    AgendaRepeat.monthly => 'Ogni mese il giorno ${start.day}',
    AgendaRepeat.yearly =>
      'Ogni anno il ${start.day} ${months[start.month - 1]}',
  };
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
    this.repeat = AgendaRepeat.none,
    this.repeatUntil,
  });

  /// Only for new events; editing keeps the series rule.
  final AgendaRepeat repeat;

  /// Last civil day of the series (inclusive), or forever when null.
  final CivilDate? repeatUntil;

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
    if (repeat != AgendaRepeat.none &&
        repeatUntil != null &&
        repeatUntil!.asLocalDate.isBefore(
          DateTime(start.year, start.month, start.day),
        )) {
      return 'La ripetizione deve finire dopo il primo evento.';
    }
    return null;
  }
}

/// Calendar preselected for a new event: the last one used if still
/// writable; otherwise a Google primary calendar shown in Agenda, any
/// calendar shown in Agenda, any Google primary, any writable one. Phones
/// often hold several Google accounts, each with its own primary calendar.
String? defaultEventCalendar(
  List<AgendaCalendar> calendars,
  String? lastUsed, {
  Set<String> hidden = const {},
}) {
  final writable = [
    for (final calendar in calendars)
      if (calendar.writable) calendar,
  ];
  final preferences = <bool Function(AgendaCalendar)>[
    (calendar) => calendar.id == lastUsed,
    (calendar) => calendar.isGooglePrimary && !hidden.contains(calendar.id),
    (calendar) => !hidden.contains(calendar.id),
    (calendar) => calendar.isGooglePrimary,
    (_) => true,
  ];
  for (final preferred in preferences) {
    for (final calendar in writable) {
      if (preferred(calendar)) return calendar.id;
    }
  }
  return null;
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
    this.answered = false,
    this.timeZone,
    this.eventZoneTimes,
    this.isOrganizer = true,
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

  /// Accepted, declined or tentative. False also when unknown: Exchange
  /// ActiveSync copies often carry no status at all.
  final bool answered;

  /// The event's own IANA zone, as stored by its calendar.
  final String? timeZone;

  /// "13:00–14:00" in [timeZone] when its offset differs from the device.
  final String? eventZoneTimes;

  /// False for invitations organised by someone else: not editable here.
  final bool isOrganizer;
}

/// A Todo task flagged for the Agenda: dates only, so shown all day.
final class AgendaTaskItem {
  const AgendaTaskItem({
    required this.id,
    required this.title,
    required this.date,
    this.completed = false,
  });

  final String id;
  final String title;
  final CivilDate date;
  final bool completed;
}

/// What the user chose to hide, on top of hidden calendars. Local only.
final class AgendaFilter {
  const AgendaFilter({
    this.hideUnanswered = false,
    this.hiddenWords = const [],
  });

  static const none = AgendaFilter();

  final bool hideUnanswered;

  /// Case- and accent-insensitive substrings of the title, e.g. "Live Broadcast".
  final List<String> hiddenWords;

  bool get isActive => hideUnanswered || hiddenWords.isNotEmpty;

  bool hidesEntry(AgendaEntry entry) => hideUnanswered && entry.unanswered;

  /// Hidden by a word. Unanswered invitations are judged after duplicates
  /// are merged ([hidesEntry]): one copy may know the answer, another not.
  bool hides(AgendaSourceEvent event) {
    final title = foldForSearch(event.title);
    return hiddenWords.any(
      (word) =>
          word.trim().isNotEmpty && title.contains(foldForSearch(word.trim())),
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
    this.timeZone,
    this.eventZoneTimes,
    this.isOrganizer = true,
    this.taskId,
    this.completed = false,
    this.unanswered = false,
  });

  /// Invitation not yet accepted or declined in any of its calendars:
  /// drawn outlined, as Google Calendar does (build 221).
  final bool unanswered;

  /// Calendar id used for Todo tasks shown in the Agenda.
  static const tasksCalendarId = 'todo-tasks';

  /// Set for a Todo task flagged "Mostra in agenda" (never a phone event).
  final String? taskId;
  final bool completed;
  bool get isTask => taskId != null;

  final String instanceId;
  final String? timeZone;
  final String? eventZoneTimes;
  final bool isOrganizer;

  /// Occurrence of a recurring series (instance ids carry `@timestamp`).
  bool get recurring => instanceId.contains('@');

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
  List<AgendaTaskItem> tasks = const [],
}) {
  final entries = mergeAgendaEntries(
    events: events,
    calendars: calendars,
    hiddenCalendarIds: hiddenCalendarIds,
    filter: filter,
    tasks: tasks,
  );
  return [
    for (var index = 0; index < days; index++)
      _day(first.addDays(index), entries),
  ];
}

/// Meetings the organiser cancelled that Exchange keeps in the calendar
/// until removed by hand, with the status still "confirmed": "Canceled:
/// TNG Meeting", "Annullato: …" (seen on the Galaxy, build 223).
bool isCanceledTitle(String title) => RegExp(
  r'^\s*(canceled|cancelled|annullato|annullata|annullati)\s*:',
  caseSensitive: false,
).hasMatch(title);

/// Visible, filtered, de-duplicated entries in display order, before they
/// are split into days. Also used by the universal search.
List<AgendaEntry> mergeAgendaEntries({
  required List<AgendaSourceEvent> events,
  required List<AgendaCalendar> calendars,
  required Set<String> hiddenCalendarIds,
  AgendaFilter filter = AgendaFilter.none,
  List<AgendaTaskItem> tasks = const [],
}) {
  final calendarOrder = {
    for (final (index, calendar) in calendars.indexed) calendar.id: index,
  };
  final visible =
      events
          .where(
            (event) =>
                !event.canceled &&
                !isCanceledTitle(event.title) &&
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
      existing.anyUnanswered |= event.unanswered;
      existing.anyAnswered |= event.answered;
    }
  }

  final entries = [
    ...merged.values
        .map((value) => value.freeze())
        .where((entry) => !filter.hidesEntry(entry)),
    for (final task in tasks)
      AgendaEntry(
        instanceId: 'task:${task.id}',
        calendarIds: const [AgendaEntry.tasksCalendarId],
        title: task.title,
        start: task.date.asLocalDate,
        end: task.date.addDays(1).asLocalDate,
        allDay: true,
        taskId: task.id,
        completed: task.completed,
      ),
  ]..sort(_compareEntries);
  return entries;
}

/// Search results: upcoming first (soonest on top), then past ones (most
/// recent on top), at most [limit].
List<AgendaEntry> orderSearchResults(
  List<AgendaEntry> entries,
  DateTime now, {
  int limit = 30,
}) {
  final upcoming = [
    for (final entry in entries)
      if (entry.end.isAfter(now)) entry,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final past = [
    for (final entry in entries)
      if (!entry.end.isAfter(now)) entry,
  ]..sort((a, b) => b.start.compareTo(a.start));
  return [...upcoming, ...past].take(limit).toList();
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
  // Calendar events first, then Todo tasks of the same day.
  if (a.isTask != b.isTask) return a.isTask ? 1 : -1;
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

  /// Unanswered when a copy says so and no copy has an answer (build 223:
  /// the Exchange copy of a KCL invitation knows neither).
  late bool anyUnanswered = source.unanswered;
  late bool anyAnswered = source.answered;

  AgendaEntry freeze() => AgendaEntry(
    instanceId: source.instanceId,
    calendarIds: List.unmodifiable(calendarIds),
    title: source.title,
    start: source.start,
    end: source.end,
    allDay: source.allDay,
    location: source.location,
    meeting: meeting,
    timeZone: source.timeZone,
    eventZoneTimes: source.eventZoneTimes,
    isOrganizer: source.isOrganizer,
    unanswered: anyUnanswered && !anyAnswered,
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
      answered: row['answered'] as bool? ?? false,
      timeZone: row['timeZone'] as String?,
      eventZoneTimes: row['eventZoneTimes'] as String?,
      isOrganizer: row['organizer'] as bool? ?? true,
    );

/// The device zone as the Agenda shows it: always the IANA id, never an
/// abbreviation, with the current UTC offset.
String zoneLabel(String ianaId, int offsetSeconds) {
  final sign = offsetSeconds < 0 ? '−' : '+';
  final minutes = offsetSeconds.abs() ~/ 60;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final offset = minutes == 0
      ? 'UTC'
      : 'UTC$sign$hours${rest == 0 ? '' : ':${rest.toString().padLeft(2, '0')}'}';
  return '$ianaId · $offset';
}

/// An entry placed on a one-day timeline, in minutes from local midnight.
final class TimelineBlock {
  const TimelineBlock({
    required this.entry,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
    this.indent = 0,
  });

  final AgendaEntry entry;
  final int startMinute;
  final int endMinute;

  /// Side-by-side slot among events starting together, 0-based, of
  /// [columns].
  final int column;
  final int columns;

  /// Cascade level: an event starting well after one it overlaps is drawn
  /// over it, shifted right by this many steps, instead of squeezing both
  /// into narrow columns (Google Calendar's layout, build 220).
  final int indent;
}

/// "ora" while [start]–[end] is under way, "tra 25 min" within the next
/// hour, otherwise null: how soon the next appointment is (build 221).
String? relativeStartLabel(DateTime start, DateTime end, DateTime now) {
  if (!now.isBefore(start) && now.isBefore(end)) return 'ora';
  final minutes = (start.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0 || minutes > 60) return null;
  return minutes == 60 ? 'tra 1 ora' : 'tra $minutes min';
}

/// Event span picked by press-and-drag on a timeline: from the quarter
/// hour pressed to the quarter hour reached, at least 15 minutes, either
/// direction, inside the day (build 221).
({int start, int end}) dragSpan(int pressedMinute, int currentMinute) {
  int snap(int minute) => ((minute / 15).round() * 15).clamp(0, 24 * 60);
  final a = snap(pressedMinute).clamp(0, 24 * 60 - 15);
  final b = snap(currentMinute);
  if (b >= a + 15) return (start: a, end: b);
  if (b <= a - 15) return (start: b, end: a);
  return (start: a, end: a + 15);
}

/// Vertical scale of a day timeline: full height for the useful hours
/// (by default 7:00–21:00, widened to every event of [blocks]), a narrow
/// band for the others, so empty nights do not push the day off screen
/// (build 221). Minutes map to offsets and back for taps and drags.
final class TimelineScale {
  TimelineScale._(this.hourHeights) : _tops = _offsets(hourHeights);

  static List<double> _offsets(List<double> heights) {
    final tops = [0.0];
    for (final height in heights) {
      tops.add(tops.last + height);
    }
    return tops;
  }

  factory TimelineScale.forBlocks(
    Iterable<TimelineBlock> blocks, {
    required double hourHeight,
    double foldedHeight = 14,
    int firstHour = 7,
    int lastHour = 21,
  }) {
    var first = firstHour;
    var last = lastHour;
    for (final block in blocks) {
      first = math.min(first, block.startMinute ~/ 60);
      last = math.max(last, (block.endMinute + 59) ~/ 60);
    }
    return TimelineScale._([
      for (var hour = 0; hour < 24; hour++)
        hour >= first && hour < last ? hourHeight : foldedHeight,
    ]);
  }

  /// Height of each hour, 0–23.
  final List<double> hourHeights;
  final List<double> _tops;

  double get total => _tops[24];

  bool isFolded(int hour) => hourHeights[hour] < hourHeights.reduce(math.max);

  /// Offset of [minute] (0–1440) from midnight.
  double y(int minute) {
    final clamped = minute.clamp(0, 24 * 60);
    final hour = math.min(clamped ~/ 60, 23);
    return _tops[hour] + (clamped - hour * 60) / 60 * hourHeights[hour];
  }

  /// Minute at offset [dy], the inverse of [y].
  int minuteAt(double dy) {
    if (dy <= 0) return 0;
    for (var hour = 0; hour < 24; hour++) {
      if (dy < _tops[hour + 1]) {
        return hour * 60 +
            ((dy - _tops[hour]) / hourHeights[hour] * 60).floor();
      }
    }
    return 24 * 60;
  }
}

/// Horizontal placement of [block] in a lane [width] wide: left offset and
/// width. Each cascade step shifts right by 12% of the lane (at most four
/// steps); columns share what is left.
({double left, double width}) timelineSlot(TimelineBlock block, double width) {
  final step = width * 0.12;
  final shift = math.min(block.indent, 4) * step;
  final columnWidth = (width - shift) / block.columns;
  return (left: shift + block.column * columnWidth, width: columnWidth);
}

/// Timed events that overlap another timed event, by instance id, with the
/// events they clash with in start order. All-day events and Todo tasks
/// never clash; touching events (one ends when the next starts) do not.
/// Duplicates were already merged, so the same meeting in two calendars is
/// not a clash.
Map<String, List<AgendaEntry>> agendaOverlaps(Iterable<AgendaEntry> entries) {
  final timed =
      entries
          .where((e) => !e.allDay && !e.isTask && e.end.isAfter(e.start))
          .toList()
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.instanceId.compareTo(b.instanceId);
        });
  final result = <String, List<AgendaEntry>>{};
  final active = <AgendaEntry>[];
  for (final entry in timed) {
    active.removeWhere((other) => !other.end.isAfter(entry.start));
    for (final other in active) {
      (result[other.instanceId] ??= []).add(entry);
      (result[entry.instanceId] ??= []).add(other);
    }
    active.add(entry);
  }
  for (final clashes in result.values) {
    clashes.sort((a, b) => a.start.compareTo(b.start));
  }
  return result;
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

  // Events starting within this window of each other share columns;
  // later overlapping ones cascade over them (see [TimelineBlock.indent]).
  const parallelWindow = 30;
  final groups = <_TimelineGroup>[];
  for (final item in placed) {
    final start = item.start.clamp(0, 24 * 60 - minMinutes);
    final end = math.min(math.max(item.end, start + minMinutes), 24 * 60);
    final active = [
      for (final group in groups)
        if (group.end > start) group,
    ];
    final parallel = active
        .where((group) => group.start + parallelWindow > start)
        .lastOrNull;
    final group =
        parallel ??
        _TimelineGroup(
          start,
          active.isEmpty ? 0 : active.map((g) => g.indent).reduce(math.max) + 1,
        );
    if (parallel == null) groups.add(group);
    // First column whose blocks have all ended by [start].
    var column = 0;
    while (group.items.any(
      (other) => other.column == column && other.end > start,
    )) {
      column++;
    }
    group.items.add((
      entry: item.entry,
      start: start,
      end: end,
      column: column,
    ));
    group.end = math.max(group.end, end);
  }
  final result = <TimelineBlock>[];
  for (final group in groups) {
    final columns = group.items.fold(
      0,
      (max, item) => item.column + 1 > max ? item.column + 1 : max,
    );
    for (final item in group.items) {
      result.add(
        TimelineBlock(
          entry: item.entry,
          startMinute: item.start,
          endMinute: item.end,
          column: item.column,
          columns: columns,
          indent: group.indent,
        ),
      );
    }
  }
  return result;
}

final class _TimelineGroup {
  _TimelineGroup(this.start, this.indent) : end = start;
  final int start;
  final int indent;
  int end;
  final items = <({AgendaEntry entry, int start, int end, int column})>[];
}

/// "London · UTC+1" from "Europe/London · UTC+1": the city part of the IANA
/// id, for the narrow Agenda header (the full label stays in details).
String shortZoneLabel(String label) {
  final parts = label.split(' · ');
  final city = parts.first.split('/').last.replaceAll('_', ' ');
  return [city, ...parts.skip(1)].join(' · ');
}

/// "sennar.pierp" from "sennar.pierp@gmail.com"; other names unchanged.
String shortCalendarName(String name) {
  final at = name.indexOf('@');
  return at > 0 ? name.substring(0, at) : name;
}

/// Working day before [date] (Friday for a Monday): when to prepare.
CivilDate previousWorkingDay(CivilDate date) {
  var day = date.addDays(-1);
  while (day.asLocalDate.weekday > DateTime.friday) {
    day = day.addDays(-1);
  }
  return day;
}

/// Working day after [date] (Monday for a Friday): when to follow up.
CivilDate nextWorkingDay(CivilDate date) {
  var day = date.addDays(1);
  while (day.asLocalDate.weekday > DateTime.friday) {
    day = day.addDays(1);
  }
  return day;
}

/// A task to prepare for, or follow up on, [event]: title, date and the
/// link written in its notes. Deterministic, no AI involved.
({String title, CivilDate date, String notes}) linkedTaskFor(
  AgendaEntry event, {
  required bool followUp,
  required String eventLabel,
}) {
  final first = CivilDate.fromDateTime(event.start);
  // All-day ends are exclusive midnights: the last day is the one before.
  final last = CivilDate.fromDateTime(
    event.allDay ? event.end.subtract(const Duration(days: 1)) : event.end,
  );
  final title = event.title.trim().isEmpty ? 'evento' : event.title.trim();
  return (
    title: followUp ? 'Follow-up: $title' : 'Preparare: $title',
    date: followUp ? nextWorkingDay(last) : previousWorkingDay(first),
    notes: 'Collegata a: $eventLabel',
  );
}
