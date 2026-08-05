import 'dart:convert';
import 'dart:io';

import 'package:device_calendar_plus/device_calendar_plus.dart';

import '../data/local/database.dart';
import '../domain/task.dart';

class CalendarExportResult {
  const CalendarExportResult({
    required this.calendarName,
    required this.eventId,
  });

  final String calendarName;
  final String eventId;
}

class CalendarService {
  CalendarService(this._database, {DeviceCalendar? calendar, bool? isAndroid})
    : _calendar = calendar ?? DeviceCalendar.instance,
      _isAndroid = isAndroid ?? Platform.isAndroid;

  final AppDatabase _database;
  final DeviceCalendar _calendar;
  final bool _isAndroid;

  Future<CalendarExportResult> exportTask(Task task) async {
    if (!_isAndroid) {
      throw UnsupportedError('Calendario disponibile solo su Android');
    }
    final dateText = task.dueDate ?? task.showDate;
    if (dateText == null) {
      throw const FormatException(
        'Imposta “Mostra il” o “Scade il” prima di aggiungere al calendario.',
      );
    }
    final permission = await _calendar.requestPermissions();
    if (permission != CalendarPermissionStatus.granted) {
      throw const FormatException('Permesso calendario non concesso.');
    }
    final calendars =
        (await _calendar.listCalendars())
            .where((calendar) => !calendar.readOnly && !calendar.hidden)
            .toList()
          ..sort(_calendarPreference);
    if (calendars.isEmpty) {
      throw const FormatException(
        'Nessun calendario modificabile disponibile.',
      );
    }
    final target = calendars.first;
    final date = CivilDate.parse(dateText);
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    final description = [
      if (task.notes != null) task.notes!,
      'Origine: Attività deterministiche (${task.id})',
    ].join('\n\n');
    final mappingKey = 'calendar_event:${task.id}';
    final mapping = await (_database.select(
      _database.appSettings,
    )..where((setting) => setting.key.equals(mappingKey))).getSingleOrNull();
    late final String eventId;
    late final String calendarName;
    if (mapping != null) {
      final decoded = jsonDecode(mapping.value) as Map<String, Object?>;
      eventId = decoded['event_id']! as String;
      calendarName = decoded['calendar_name']! as String;
      await _calendar.updateEvent(
        eventId: eventId,
        title: task.title,
        description: Patch.set(description),
        startDate: start,
        endDate: end,
        isAllDay: true,
        timeZone: null,
      );
    } else {
      eventId = await _calendar.createEvent(
        calendarId: target.id,
        title: task.title,
        description: description,
        startDate: start,
        endDate: end,
        isAllDay: true,
        timeZone: null,
      );
      calendarName = target.name;
      await _database
          .into(_database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: mappingKey,
              value: jsonEncode({
                'event_id': eventId,
                'calendar_id': target.id,
                'calendar_name': calendarName,
              }),
            ),
          );
    }
    return CalendarExportResult(calendarName: calendarName, eventId: eventId);
  }

  static int _calendarPreference(Calendar left, Calendar right) {
    int score(Calendar calendar) {
      final google =
          calendar.accountType?.toLowerCase().contains('google') ?? false;
      return (google ? 2 : 0) + (calendar.isPrimary ? 1 : 0);
    }

    final byScore = score(right).compareTo(score(left));
    if (byScore != 0) return byScore;
    final byName = left.name.compareTo(right.name);
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }
}
