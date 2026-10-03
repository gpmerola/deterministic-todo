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

  static const hiddenCalendarsKey = 'agenda_hidden_calendars';

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

  /// Calendars the system marks visible, grouped by account then name.
  Future<List<AgendaCalendar>> calendars() async {
    final result = [
      for (final calendar in await _calendar.listCalendars())
        if (!calendar.hidden)
          AgendaCalendar(
            id: calendar.id,
            name: calendar.name,
            accountName: calendar.accountName ?? '',
            colorHex: calendar.colorHex,
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

  Future<Set<String>> hiddenCalendarIds() async {
    final row =
        await (_database.select(_database.appSettings)
              ..where((setting) => setting.key.equals(hiddenCalendarsKey)))
            .getSingleOrNull();
    if (row == null) return {};
    try {
      return {for (final id in jsonDecode(row.value) as List) id as String};
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<void> setHiddenCalendarIds(Set<String> ids) => _database
      .into(_database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: hiddenCalendarsKey,
          value: jsonEncode(ids.toList()..sort()),
        ),
      );
}
