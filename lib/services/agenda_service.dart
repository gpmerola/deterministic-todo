import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';
import '../domain/task.dart' show CivilDate;
import 'agenda_tasks.dart';

enum AgendaAccess { granted, askable, denied }

/// A whole month per screen is the default (build 205); the choice is kept.
enum AgendaViewMode { week, twoWeeks, month, list }

/// Access to every calendar the Android system provider holds, including
/// Outlook/Exchange accounts synced by their own apps. Events are read on
/// demand and never stored, logged or synchronised; they are written only on
/// an explicit create, edit or delete.
class AgendaService {
  AgendaService(this._database, {DeviceCalendar? calendar})
    : _calendar = calendar ?? DeviceCalendar.instance;

  /// `{calendarId: shown}` chosen in Agenda; device-local, never synced.
  static const calendarChoicesKey = 'agenda_calendar_choices';

  /// Renamed in build 205 when Month became the default again, so a stored
  /// two-week choice from earlier builds does not override it once.
  static const viewModeKey = 'agenda_view_mode_v2';
  static const lastEventCalendarKey = 'agenda_last_event_calendar';

  /// `{"hide_unanswered": bool, "words": [String]}`; device-local.
  static const filterKey = 'agenda_filter';

  /// Build 191 stored only hidden IDs; read once as explicit "hidden" choices.
  static const legacyHiddenCalendarsKey = 'agenda_hidden_calendars';

  final AppDatabase _database;
  final DeviceCalendar _calendar;

  static const _channel = MethodChannel('app.deterministic.todo/agenda');

  /// Last results, kept in memory only so reopening Agenda paints at once and
  /// then revalidates. Never written to disk.
  List<AgendaCalendar>? lastCalendars;
  Map<String, bool>? lastChoices;
  AgendaViewMode? lastMode;
  AgendaFilter? lastFilter;
  String? lastZoneLabel;
  final Map<String, List<AgendaSourceEvent>> _events = {};
  final Map<String, List<AgendaTaskItem>> _tasks = {};
  late final taskLinks = AgendaTaskLinks(_database);
  static const _maxCachedRanges = 64;

  static String _rangeKey(DateTime start, DateTime end, List<String> ids) =>
      '${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|'
      '${ids.join(',')}';

  /// Events of a range read earlier in this session, if any.
  List<AgendaSourceEvent>? cachedEvents(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) => _events[_rangeKey(start, end, calendarIds)];

  Future<AgendaAccess> access() async =>
      switch (await _calendar.hasPermissions()) {
        CalendarPermissionStatus.granted => AgendaAccess.granted,
        CalendarPermissionStatus.notDetermined => AgendaAccess.askable,
        _ => AgendaAccess.denied,
      };

  Future<AgendaAccess> requestAccess() async {
    final status = await _calendar.requestPermissions();
    return status == CalendarPermissionStatus.granted
        ? AgendaAccess.granted
        : await access();
  }

  Future<void> openSystemSettings() => _calendar.openAppSettings();

  /// Every calendar on the phone, grouped by account then name. Calendars
  /// hidden in the phone's calendar app are listed too, off by default.
  Future<List<AgendaCalendar>> calendars() async {
    final result = [
      for (final calendar in await _calendar.listCalendars())
        AgendaCalendar(
          id: calendar.id,
          name: calendar.name,
          accountName: calendar.accountName ?? '',
          colorHex: calendar.colorHex,
          visibleBySystem: !calendar.hidden,
          writable: !calendar.readOnly,
          isGooglePrimary:
              calendar.isPrimary &&
              (calendar.accountType?.contains('google') ?? false),
        ),
    ];
    result.sort((a, b) {
      final byAccount = a.accountName.compareTo(b.accountName);
      if (byAccount != 0) return byAccount;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return lastCalendars = result;
  }

  /// One provider query per range through [AgendaChannel]; descriptions are
  /// reduced natively to meeting URLs.
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    if (calendarIds.isEmpty) return const [];
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('instances', {
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
          'calendarIds': calendarIds,
        }) ??
        const [];
    final result = [for (final row in rows) agendaEventFromRow(row)];
    if (_events.length >= _maxCachedRanges) _events.clear();
    _events[_rangeKey(start, end, calendarIds)] = result;
    return result;
  }

  /// Opens the occurrence in the phone's own calendar app.
  Future<void> openEvent(String instanceId) =>
      _calendar.showEventModal(instanceId);

  Future<Map<String, bool>> calendarChoices() async =>
      lastChoices = await _readChoices();

  Future<Map<String, bool>> _readChoices() async {
    final rows =
        await (_database.select(_database.appSettings)..where(
              (setting) => setting.key.isIn([
                calendarChoicesKey,
                legacyHiddenCalendarsKey,
              ]),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    try {
      final current = values[calendarChoicesKey];
      if (current != null) {
        return {
          for (final entry in (jsonDecode(current) as Map).entries)
            entry.key as String: entry.value as bool,
        };
      }
      final legacy = values[legacyHiddenCalendarsKey];
      if (legacy == null) return {};
      return {for (final id in jsonDecode(legacy) as List) id as String: false};
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<void> saveCalendarChoices(Map<String, bool> choices) {
    lastChoices = Map.of(choices);
    return _saveChoices(choices);
  }

  Future<void> _saveChoices(Map<String, bool> choices) => _database
      .into(_database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: calendarChoicesKey,
          value: jsonEncode(
            Map.fromEntries(
              choices.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
            ),
          ),
        ),
      );

  /// Month grid unless the list was chosen explicitly.
  Future<AgendaViewMode> viewMode() async => lastMode = await _readMode();

  Future<AgendaViewMode> _readMode() async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((setting) => setting.key.equals(viewModeKey))).getSingleOrNull();
    return AgendaViewMode.values.firstWhere(
      (mode) => mode.name == row?.value,
      orElse: () => AgendaViewMode.month,
    );
  }

  Future<void> saveViewMode(AgendaViewMode mode) {
    lastMode = mode;
    return _saveMode(mode);
  }

  Future<void> _saveMode(AgendaViewMode mode) => _database
      .into(_database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: viewModeKey, value: mode.name),
      );

  Future<AgendaFilter> filter() async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((setting) => setting.key.equals(filterKey))).getSingleOrNull();
    var result = AgendaFilter.none;
    if (row != null) {
      try {
        final decoded = jsonDecode(row.value) as Map;
        result = AgendaFilter(
          hideUnanswered: decoded['hide_unanswered'] as bool? ?? false,
          hiddenWords: [
            for (final word in decoded['words'] as List? ?? const [])
              word as String,
          ],
        );
      } on FormatException {
        result = AgendaFilter.none;
      } on TypeError {
        result = AgendaFilter.none;
      }
    }
    return lastFilter = result;
  }

  Future<void> saveFilter(AgendaFilter filter) {
    lastFilter = filter;
    return _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: filterKey,
            value: jsonEncode({
              'hide_unanswered': filter.hideUnanswered,
              'words': filter.hiddenWords,
            }),
          ),
        );
  }

  Future<String?> lastEventCalendar() async =>
      (await (_database.select(_database.appSettings)
                ..where((setting) => setting.key.equals(lastEventCalendarKey)))
              .getSingleOrNull())
          ?.value;

  /// Writes [draft] into its phone calendar with the system IANA time zone;
  /// the account's own sync uploads it. Returns the new event id.
  Future<String> createEvent(AgendaEventDraft draft) async {
    final id = await _calendar.createEvent(
      calendarId: draft.calendarId,
      title: draft.title.trim(),
      startDate: draft.start,
      endDate: draft.end,
      isAllDay: draft.allDay,
      location: _blankToNull(draft.location),
      description: _blankToNull(draft.notes),
      recurrenceRule: recurrenceRuleFor(draft),
    );
    _events.clear();
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastEventCalendarKey,
            value: draft.calendarId,
          ),
        );
    return id;
  }

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  /// IANA id and offset of the phone's zone, e.g. `Europe/London · UTC+1`.
  /// Null when the platform cannot tell: the UI says so instead of guessing.
  Future<String?> deviceZoneLabel() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'deviceZone',
      );
      final id = value?['id'] as String?;
      final offset = value?['offsetSeconds'] as int?;
      if (id == null || offset == null) return null;
      return lastZoneLabel = zoneLabel(id, offset);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Full occurrence for the edit form, including notes the Agenda never
  /// keeps in memory. Null when the event no longer exists.
  Future<AgendaEventDraft?> draftFor(String instanceId) async {
    final event = await _calendar.getEvent(instanceId);
    if (event == null) return null;
    return AgendaEventDraft(
      calendarId: event.calendarId,
      title: event.title,
      start: event.startDate,
      end: event.endDate,
      allDay: event.isAllDay,
      location: event.location,
      notes: event.description,
    );
  }

  /// Applies [draft] to one occurrence, or with [series] to every occurrence
  /// (the series moves by the same wall-clock shift as this occurrence).
  Future<void> updateEvent(
    String instanceId,
    AgendaEventDraft draft, {
    bool series = false,
  }) async {
    Patch<String> patch(String? value) => _blankToNull(value) == null
        ? const Patch.clear()
        : Patch.set(_blankToNull(value)!);
    if (series) {
      await _calendar.updateRecurring(
        instanceId,
        EventSpan.allEvents,
        title: draft.title.trim(),
        start: draft.start,
        duration: draft.end.difference(draft.start),
        isAllDay: draft.allDay,
        location: patch(draft.location),
        description: patch(draft.notes),
      );
    } else {
      await _calendar.updateEvent(
        eventId: instanceId,
        title: draft.title.trim(),
        startDate: draft.start,
        endDate: draft.end,
        isAllDay: draft.allDay,
        location: patch(draft.location),
        description: patch(draft.notes),
      );
    }
    _events.clear();
  }

  /// Deletes one occurrence, or with [series] the whole series.
  Future<void> deleteEvent(String instanceId, {bool series = false}) async {
    if (series) {
      await _calendar.deleteRecurring(instanceId, EventSpan.allEvents);
    } else {
      await _calendar.deleteEvent(eventId: instanceId);
    }
    _events.clear();
  }

  /// Todo tasks flagged "Mostra in agenda" in [first, first + days).
  Future<List<AgendaTaskItem>> tasks(CivilDate first, int days) async {
    final result = await taskLinks.tasksBetween(first, days);
    if (_tasks.length >= _maxCachedRanges) _tasks.clear();
    return _tasks['$first|$days'] = result;
  }

  List<AgendaTaskItem>? cachedTasks(CivilDate first, int days) =>
      _tasks['$first|$days'];

  /// Plugin rule for a new event's repetition; the weekday or day of month
  /// is implicit from the start, as Android's calendar expects.
  static RecurrenceRule? recurrenceRuleFor(AgendaEventDraft draft) {
    final until = draft.repeatUntil;
    // Inclusive last day: the end of that civil day, in UTC as RRULE wants.
    final end = until == null
        ? null
        : UntilEnd(
            DateTime(until.year, until.month, until.day, 23, 59, 59).toUtc(),
          );
    return switch (draft.repeat) {
      AgendaRepeat.none => null,
      AgendaRepeat.daily => DailyRecurrence(end: end),
      AgendaRepeat.weekdays => WeeklyRecurrence(
        daysOfWeek: const [
          DayOfWeek.monday,
          DayOfWeek.tuesday,
          DayOfWeek.wednesday,
          DayOfWeek.thursday,
          DayOfWeek.friday,
        ],
        end: end,
      ),
      AgendaRepeat.weekly => WeeklyRecurrence(end: end),
      AgendaRepeat.monthly => MonthlyByDate(end: end),
      AgendaRepeat.yearly => YearlyByDate(end: end),
    };
  }

  /// Events whose title contains [text] in the calendars shown in Agenda
  /// (filters applied), from a year ago to two years ahead. Empty without
  /// calendar access. Nothing is stored.
  Future<List<AgendaEntry>> searchEvents(String text, DateTime now) async {
    final query = text.trim();
    if (query.length < 2 || await access() != AgendaAccess.granted) {
      return const [];
    }
    final calendarList = lastCalendars ?? await calendars();
    final hidden = hiddenAgendaCalendars(
      calendarList,
      lastChoices ?? await calendarChoices(),
    );
    final ids = [
      for (final calendar in calendarList)
        if (!hidden.contains(calendar.id)) calendar.id,
    ];
    if (ids.isEmpty) return const [];
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('instances', {
          'start': DateTime(
            now.year - 1,
            now.month,
            now.day,
          ).millisecondsSinceEpoch,
          'end': DateTime(
            now.year + 2,
            now.month,
            now.day,
          ).millisecondsSinceEpoch,
          'calendarIds': ids,
          'titleQuery': query,
        }) ??
        const [];
    return orderSearchResults(
      mergeAgendaEntries(
        events: [for (final row in rows) agendaEventFromRow(row)],
        calendars: calendarList,
        hiddenCalendarIds: hidden,
        filter: lastFilter ?? await filter(),
      ),
      now,
    );
  }

  /// Explicit choice of the calendar for new events (Agenda › Calendari);
  /// the same key also remembers the last calendar used.
  Future<void> saveEventCalendar(String calendarId) => _database
      .into(_database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: lastEventCalendarKey,
          value: calendarId,
        ),
      );
}
