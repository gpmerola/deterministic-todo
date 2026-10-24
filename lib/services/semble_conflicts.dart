import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/agenda.dart';
import '../domain/semble_availability.dart';
import '../domain/semble_bookings.dart';
import 'agenda_reminders.dart';
import 'agenda_service.dart';
import 'semble_service.dart';

/// Background check for events that arrived in bookable Semble time while
/// the app was closed (build 304): run with the reminder refresh, which the
/// calendar provider's change trigger and the daily job start. No polling and
/// no Semble call: the rules come from the last read cached on the phone.
/// The notification carries day and time only, never the title.
class SembleConflicts {
  SembleConflicts(this.service, {SembleSettings? settings})
    : settings = settings ?? SembleSettings();

  final AgendaService service;
  final SembleSettings settings;

  static const days = 14;

  Future<void> check({DateTime Function() now = DateTime.now}) async {
    try {
      final config = await settings.read();
      if (!config.ready || !config.enabled) return;
      if (!await settings.conflictAlerts()) return;
      final cache = await settings.cachedRules();
      if (cache == null) return;
      if (await service.access() != AgendaAccess.granted) return;
      final at = now();
      final until = DateTime(at.year, at.month, at.day + days);
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
      if (ids.isEmpty) return;
      final semble = {
        for (final c in calendars)
          if (isSembleCalendar(c)) c.id,
      };
      final entries = mergeAgendaEntries(
        events: await service.events(
          DateTime(at.year, at.month, at.day),
          until,
          ids,
        ),
        calendars: calendars,
        hiddenCalendarIds: hidden,
        filter: filter,
      );
      final found = sembleConflicts(
        entries: entries,
        rules: cache.rules,
        first: cache.first,
        last: cache.last,
        now: at,
        until: until,
        isVisit: (entry) =>
            entry.isSembleBooking || entry.calendarIds.any(semble.contains),
      );
      final ignored = await settings.ignoredOverlaps(now: at);
      await AgendaReminders.channel.invokeMethod<int>('notifySembleConflicts', {
        'events': sembleConflictPlan([
          for (final entry in found)
            if (!ignored.containsKey(sembleOverlapKey(entry))) entry,
        ]),
      });
    } catch (_) {
      // Never logged: provider errors can carry calendar details.
    }
  }
}

/// Opaque id per occurrence, plus its times: nothing else crosses the
/// notification channel.
List<Map<String, Object>> sembleConflictPlan(Iterable<AgendaEntry> entries) => [
  for (final entry in entries)
    {
      'id': sha256
          .convert(
            utf8.encode(
              'semble|${entry.instanceId}|${entry.start.millisecondsSinceEpoch}',
            ),
          )
          .toString(),
      'start': entry.start.millisecondsSinceEpoch,
      'end': entry.end.millisecondsSinceEpoch,
    },
];
