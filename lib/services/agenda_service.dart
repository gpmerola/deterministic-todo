import 'dart:convert';

import 'package:device_calendar_plus/device_calendar_plus.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';

enum AgendaAccess { granted, askable, denied }

/// Read-only access to every calendar the Android system provider holds,
/// including Outlook/Exchange accounts synced by their own apps. Events are
/// read on demand and never stored, logged or synchronised.
class AgendaService {
  AgendaService(this._database, {DeviceCalendar? calendar})
    : _calendar = calendar ?? DeviceCalendar.instance;

  /// `{calendarId: shown}` chosen in Agenda; device-local, never synced.
  static const calendarChoicesKey = 'agenda_calendar_choices';

  /// Build 191 stored only hidden IDs; read once as explicit "hidden" choices.
  static const legacyHiddenCalendarsKey = 'agenda_hidden_calendars';

  final AppDatabase _database;
  final DeviceCalendar _calendar;

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
    return result;
  }

  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    if (calendarIds.isEmpty) return const [];
    final events = await _calendar.listEvents(
      start,
      end,
      calendarIds: calendarIds,
    );
    return [
      for (final event in events)
        AgendaSourceEvent(
          instanceId: event.instanceId,
          calendarId: event.calendarId,
          title: event.title,
          start: event.startDate,
          end: event.endDate,
          allDay: event.isAllDay,
          location: event.location,
          description: event.description,
          url: event.url,
          canceled: event.status == EventStatus.canceled,
        ),
    ];
  }

  /// Opens the occurrence in the phone's own calendar app.
  Future<void> openEvent(String instanceId) =>
      _calendar.showEventModal(instanceId);

  Future<Map<String, bool>> calendarChoices() async {
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

  Future<void> saveCalendarChoices(Map<String, bool> choices) => _database
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
}
