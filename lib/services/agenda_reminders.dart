import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';
import '../domain/task.dart';
import 'agenda_service.dart';

/// Local phone preference; deliberately independent of account/cloud sync.
class AgendaReminders {
  AgendaReminders(this.service);

  final AgendaService service;
  static const key = 'agenda_reminders_enabled';
  static const channel = MethodChannel('app.deterministic.todo/agenda');
  static const permissions = MethodChannel(
    'app.deterministic.todo/agenda_reminder_permissions',
  );

  Future<bool> enabled() async =>
      (await (service.database.select(
        service.database.appSettings,
      )..where((row) => row.key.equals(key))).getSingleOrNull())?.value !=
      'false';

  Future<void> setEnabled(bool value) async {
    await service.database
        .into(service.database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: '$value'),
        );
    await refresh();
  }

  Future<Map<Object?, Object?>> status() async =>
      await channel.invokeMapMethod<Object?, Object?>('reminderStatus') ?? {};

  Future<void> requestPermissions({bool automatic = false}) async {
    await permissions.invokeMethod<void>(automatic ? 'requestOnce' : 'request');
  }

  /// Fresh provider/settings reads: never the visible month's cached data.
  /// Bounded to seven days, refreshed on provider changes and daily offline.
  static final _queues = Expando<_ReminderQueue>();

  Future<void> refresh() {
    final queue = _queues[service.database] ??= _ReminderQueue();
    final work = queue.pending.then((_) => _refresh());
    queue.pending = work.catchError((Object _) {});
    return work;
  }

  Future<void> _refresh() async {
    // Native generation also orders separate foreground/headless isolates.
    // A refresh started before a toggle/filter change cannot restore its plan.
    final generation = await channel.invokeMethod<int>('beginReminders');
    final on = await enabled();
    final access = on ? await service.access() : AgendaAccess.denied;
    if (!on || access != AgendaAccess.granted) {
      await channel.invokeMethod<void>('replaceReminders', {
        'generation': generation,
        'enabled': on,
        'accessible': access == AgendaAccess.granted,
        'events': <Object>[],
      });
      return;
    }
    final now = DateTime.now();
    final first = CivilDate.fromDateTime(now);
    final calendars = await service.calendars();
    final filter = await service.filter();
    final hidden = hiddenAgendaCalendars(
      calendars,
      await service.calendarChoices(),
      hideHolidays: filter.hideHolidays,
    );
    final events = await service.events(
      first.asLocalDate,
      first.addDays(8).asLocalDate,
      [
        for (final c in calendars)
          if (!hidden.contains(c.id)) c.id,
      ],
    );
    final days = buildAgenda(
      events: events,
      tasks: const [],
      calendars: calendars,
      hiddenCalendarIds: hidden,
      filter: filter,
      first: first,
      days: 8,
    );
    await channel.invokeMethod<void>('replaceReminders', {
      'generation': generation,
      'enabled': true,
      'accessible': true,
      'events': reminderPlan(days.expand((d) => d.entries), now),
    });
  }

  /// Foreground failures must not block the Calendar or create unhandled errors.
  Future<void> foreground({bool requestPermission = false}) async {
    try {
      await refresh();
      if (requestPermission &&
          await enabled() &&
          await service.access() == AgendaAccess.granted) {
        await requestPermissions(automatic: true);
      }
    } on MissingPluginException {
      // Other platforms and widget tests.
    } catch (_) {
      // Provider/storage unavailable: leave the last plan and retry next trigger.
      // Errors may contain event details and must never be logged.
    }
  }
}

/// One notification per merged occurrence, even across midnight/DST. Only
/// timed events; tasks and all-day entries have no meaningful reminder time.
List<Map<String, Object>> reminderPlan(
  Iterable<AgendaEntry> entries,
  DateTime now,
) {
  final result = <String, Map<String, Object>>{};
  for (final entry in entries) {
    if (entry.allDay || entry.isTask || !entry.start.isAfter(now)) continue;
    final id = sha256
        .convert(
          utf8.encode(
            '${entry.key.isEmpty ? entry.instanceId : entry.key}|'
            '${entry.start.millisecondsSinceEpoch}',
          ),
        )
        .toString();
    result[id] = {
      'id': id,
      'eventId': entry.instanceId.split('@').first,
      'title': entry.title,
      'start': entry.start.millisecondsSinceEpoch,
      'at': entry.start
          .subtract(const Duration(minutes: 30))
          .millisecondsSinceEpoch,
    };
  }
  return result.values.toList()..sort((a, b) {
    final byTime = (a['at']! as int).compareTo(b['at']! as int);
    return byTime != 0
        ? byTime
        : (a['id']! as String).compareTo(b['id']! as String);
  });
}

class _ReminderQueue {
  Future<void> pending = Future<void>.value();
}
