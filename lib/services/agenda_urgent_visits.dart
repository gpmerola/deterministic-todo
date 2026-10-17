import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/agenda.dart';
import 'agenda_reminders.dart';
import 'agenda_service.dart';

/// Explicit visit labels observed in calendar titles; never infer from people,
/// notes, calendar names or Todo priority. Negation wins over an urgent label.
bool isUrgentVisitTitle(String title) {
  if (RegExp(
    r'\b(?:non|not|no)\s*[-–—:]?\s*urgent[ei]?\b',
    caseSensitive: false,
  ).hasMatch(title)) {
    return false;
  }
  return RegExp(r'\burgent[ei]?\b', caseSensitive: false).hasMatch(title) &&
      RegExp(
        r'\b(?:visita|visite|consulto|consultazione|consultation|appointment|assessment)\b|\bfollow[\s‐‑–-]?up\b',
        caseSensitive: false,
      ).hasMatch(title);
}

List<Map<String, Object>> urgentVisitPlan(
  Iterable<AgendaEntry> entries,
  DateTime now,
  DateTime until,
) {
  final result = <String, Map<String, Object>>{};
  for (final entry in entries) {
    if (entry.isTask ||
        !entry.end.isAfter(now) ||
        !entry.start.isBefore(until) ||
        !isUrgentVisitTitle(entry.title)) {
      continue;
    }
    // Title edits do not make an already announced occurrence new. No title
    // or patient information crosses the notification channel or is persisted.
    final id = sha256
        .convert(
          utf8.encode(
            '${entry.instanceId}|${entry.start.millisecondsSinceEpoch}',
          ),
        )
        .toString();
    result[id] = {
      'id': id,
      'start': entry.start.millisecondsSinceEpoch,
      'end': entry.end.millisecondsSinceEpoch,
    };
  }
  return result.values.toList()
    ..sort((a, b) => (a['start']! as int).compareTo(b['start']! as int));
}

/// Only called on cold start / background-to-foreground, never by headless
/// sync or provider observers. Coalesce overlapping resumes for this database.
class AgendaUrgentVisits {
  AgendaUrgentVisits(this.service);
  final AgendaService service;
  static final _running = Expando<Future<void>>();

  Future<void> foreground() {
    final pending = _running[service.database];
    if (pending != null) return pending;
    final work = _check().whenComplete(() => _running[service.database] = null);
    _running[service.database] = work;
    return work;
  }

  Future<void> _check() async {
    try {
      if (await service.access() != AgendaAccess.granted) return;
      final now = DateTime.now();
      final until = DateTime(now.year, now.month, now.day + 90);
      final calendars = await service.calendars();
      final filter = await service.filter();
      final hidden = hiddenAgendaCalendars(
        calendars,
        await service.calendarChoices(),
        hideHolidays: filter.hideHolidays,
      );
      final ids = [
        for (final c in calendars)
          if (!hidden.contains(c.id)) c.id,
      ];
      final events = ids.isEmpty
          ? <AgendaSourceEvent>[]
          : await service.events(
              DateTime(now.year, now.month, now.day),
              until,
              ids,
            );
      final entries = mergeAgendaEntries(
        events: events,
        calendars: calendars,
        hiddenCalendarIds: hidden,
        filter: filter,
      );
      await AgendaReminders.channel.invokeMethod<int>('notifyUrgentVisits', {
        'events': urgentVisitPlan(entries, now, until),
      });
    } catch (_) {
      // A revoked permission or unavailable provider must not block startup.
      // Never log provider errors: they can contain private calendar details.
    }
  }
}
