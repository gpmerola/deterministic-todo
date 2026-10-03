import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';

enum AgendaAccess { granted, askable, denied }

enum AgendaViewMode { month, list }

/// Read-only access to every calendar the Android system provider holds,
/// including Outlook/Exchange accounts synced by their own apps. Events are
/// read on demand and never stored, logged or synchronised.
class AgendaService {
  AgendaService(this._database, {DeviceCalendar? calendar})
    : _calendar = calendar ?? DeviceCalendar.instance;

  /// `{calendarId: shown}` chosen in Agenda; device-local, never synced.
  static const calendarChoicesKey = 'agenda_calendar_choices';

  static const viewModeKey = 'agenda_view_mode';

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
  final Map<String, List<AgendaSourceEvent>> _events = {};
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
    return row?.value == AgendaViewMode.list.name
        ? AgendaViewMode.list
        : AgendaViewMode.month;
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
}
