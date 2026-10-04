import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agenda.dart';
import '../domain/task.dart';
import 'agenda_service.dart';

/// Payload for `replace_agenda_snapshot_v1`: what the phone's Agenda shows
/// (calendars shown, filters applied, duplicates merged) in [first, first +
/// days). Tasks are excluded: the web has its own copy of the task list and
/// only needs the "Mostra in agenda" keys.
Map<String, Object?> buildAgendaMirror({
  required List<AgendaDay> days,
  required List<AgendaCalendar> calendars,
  required CivilDate first,
  required int count,
  required String deviceId,
  required String? zoneLabel,
  required Set<String> taskLinks,
  String? mainCalendarId,
  String? aiCalendarId,
}) {
  final seen = <String>{};
  final events = <Map<String, Object?>>[];
  for (final day in days) {
    for (final entry in day.entries) {
      if (entry.isTask || !seen.add(entry.instanceId)) continue;
      events.add({
        'instance_key': entry.instanceId,
        'calendar_keys': entry.calendarIds,
        'title': entry.title,
        'location': entry.location,
        'starts_at': entry.start.toUtc().toIso8601String(),
        'ends_at': entry.end.toUtc().toIso8601String(),
        'all_day': entry.allDay,
        // All-day spans travel as civil dates (end exclusive) so another
        // time zone does not shift them.
        if (entry.allDay)
          'start_date': CivilDate.fromDateTime(entry.start).toString(),
        if (entry.allDay)
          'end_date': CivilDate.fromDateTime(entry.end).toString(),
        'meeting_provider': entry.meeting?.provider,
        'meeting_url': entry.meeting?.url.toString(),
        'time_zone': entry.timeZone,
        'event_zone_times': entry.eventZoneTimes,
        'is_organizer': entry.isOrganizer,
      });
    }
  }
  return {
    'device_id': deviceId,
    'zone_label': zoneLabel,
    'window_start': first.asLocalDate.toUtc().toIso8601String(),
    'window_end': first.addDays(count).asLocalDate.toUtc().toIso8601String(),
    'calendars': [
      for (final calendar in calendars)
        {
          'key': calendar.id,
          'name': calendar.name,
          'account': calendar.accountName,
          'color': calendar.colorHex,
          // The web offers editing only where the phone can write.
          'writable': calendar.writable,
          // «Nuovi eventi in» and the ✨ calendar, as defaults on the web.
          if (calendar.id == mainCalendarId) 'main': true,
          if (calendar.id == aiCalendarId) 'ai': true,
        },
    ],
    'task_links': taskLinks.toList()..sort(),
    'events': events,
  };
}

/// Sends the phone Agenda to Supabase for the read-only web Agenda: on app
/// start/resume at most every [minInterval], and right after an Agenda
/// change. No background work and no timers.
class AgendaMirror {
  AgendaMirror({
    required this.service,
    required this.client,
    required this.deviceId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const minInterval = Duration(minutes: 10);
  static const daysBack = 30;
  static const daysAhead = 90;

  final AgendaService service;
  final SupabaseClient client;
  final String deviceId;
  final DateTime Function() _now;
  DateTime? _last;
  bool _busy = false;

  Future<void> uploadIfStale() async {
    final last = _last;
    if (last != null && _now().difference(last) < minInterval) return;
    await upload();
  }

  /// One atomic replacement of the mirror; false when skipped (not signed
  /// in, no calendar access, already running) or failed. Failures are
  /// silent: the next start or change retries, the web shows the old copy.
  Future<bool> upload() async {
    if (_busy || client.auth.currentSession == null) return false;
    _busy = true;
    try {
      if (await service.access() != AgendaAccess.granted) return false;
      final now = _now();
      final first = CivilDate.fromDateTime(now).addDays(-daysBack);
      const count = daysBack + daysAhead + 1;
      final days = await service.agendaDays(first, count);
      final payload = buildAgendaMirror(
        days: days,
        calendars: await service.shownCalendars(),
        first: first,
        count: count,
        deviceId: deviceId,
        zoneLabel: await service.deviceZoneLabel(),
        taskLinks: await service.taskLinks.keys(),
        mainCalendarId: await service.lastEventCalendar(),
        aiCalendarId: await service.aiEventCalendar(),
      );
      await client.rpc(
        'replace_agenda_snapshot_v1',
        params: {'snapshot': payload},
      );
      _last = now;
      return true;
    } catch (_) {
      // Not logged: the payload carries event titles.
      return false;
    } finally {
      _busy = false;
    }
  }
}
