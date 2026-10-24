import 'dart:async';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import '../../services/agenda_service.dart';
import '../../services/semble_service.dart';

class AgendaLoadResult {
  const AgendaLoadResult({
    required this.access,
    required this.revision,
    this.zone,
    this.mode,
    this.filter,
    this.calendars,
    this.hidden,
  });
  final AgendaAccess access;
  final int revision;
  final String? zone;
  final AgendaViewMode? mode;
  final AgendaFilter? filter;
  final List<AgendaCalendar>? calendars;
  final Set<String>? hidden;
}

/// Owns calendar reads independently of widgets. Equivalent overlapping reads
/// share one result; edits arriving during a read queue exactly one fresh pass.
class AgendaLoadController {
  AgendaLoadController(this.service);
  final AgendaService service;
  Future<AgendaLoadResult>? _active;
  bool _again = false;
  bool _disposed = false;
  int _revision = 0;

  /// Calendars, choices and settings; the views read their own days with
  /// [readDays].
  Future<AgendaLoadResult> load({bool changed = false}) {
    if (_active != null) {
      _again |= changed;
      return _active!;
    }
    return _active = _drain().whenComplete(() => _active = null);
  }

  Future<AgendaLoadResult> _drain() async {
    late AgendaLoadResult result;
    do {
      _again = false;
      try {
        result = await _read();
      } catch (_) {
        if (!_again || _disposed) rethrow;
      }
    } while (_again && !_disposed);
    return result;
  }

  Future<AgendaLoadResult> _read() async {
    final access = await service.access();
    if (access != AgendaAccess.granted) {
      return AgendaLoadResult(access: access, revision: ++_revision);
    }
    final (zone, mode, filter, calendars, choices) = await (
      service.deviceZoneLabel(),
      service.viewMode(),
      service.filter(),
      service.calendars(),
      service.calendarChoices(),
    ).wait;
    final hidden = hiddenAgendaCalendars(
      calendars,
      choices,
      hideHolidays: filter.hideHolidays,
    );
    return AgendaLoadResult(
      access: access,
      revision: ++_revision,
      zone: zone,
      mode: mode,
      filter: filter,
      calendars: calendars,
      hidden: hidden,
    );
  }

  Future<List<AgendaDay>> readDays(
    List<AgendaCalendar> calendars,
    Set<String> hidden,
    AgendaFilter filter,
    CivilDate first,
    int count,
  ) async {
    final (events, tasks) = await (
      service.events(first.asLocalDate, first.addDays(count).asLocalDate, [
        for (final calendar in calendars)
          if (!hidden.contains(calendar.id)) calendar.id,
      ]),
      service.tasks(first, count),
    ).wait;
    return buildAgenda(
      events: events,
      tasks: tasks,
      calendars: calendars,
      hiddenCalendarIds: hidden,
      filter: filter,
      first: first,
      days: count,
      adjust: SembleLayer.shared.adjustEntries(calendars, hidden),
    );
  }

  void dispose() {
    _disposed = true;
  }
}
