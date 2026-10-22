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
    this.days,
  });
  final AgendaAccess access;
  final int revision;
  final String? zone;
  final AgendaViewMode? mode;
  final AgendaFilter? filter;
  final List<AgendaCalendar>? calendars;
  final Set<String>? hidden;
  final List<AgendaDay>? days;
}

/// Owns calendar reads independently of widgets. Equivalent overlapping reads
/// share one result; edits arriving during a read queue exactly one fresh pass.
class AgendaLoadController {
  AgendaLoadController(this.service);
  final AgendaService service;
  Future<AgendaLoadResult>? _active;
  (CivilDate, int)? _requested;
  bool _again = false;
  bool _disposed = false;
  int _revision = 0;

  Future<AgendaLoadResult> load(
    CivilDate first,
    int count, {
    bool changed = false,
  }) {
    final request = (first, count);
    if (_active != null) {
      _again |= changed || _requested != request;
      _requested = request;
      return _active!;
    }
    _requested = request;
    return _active = _drain().whenComplete(() => _active = null);
  }

  Future<AgendaLoadResult> _drain() async {
    late AgendaLoadResult result;
    do {
      _again = false;
      final (first, count) = _requested!;
      try {
        result = await _read(first, count);
      } catch (_) {
        if (!_again || _disposed) rethrow;
      }
    } while (_again && !_disposed);
    return result;
  }

  Future<AgendaLoadResult> _read(CivilDate first, int count) async {
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
    final days = mode == AgendaViewMode.list
        ? await readDays(calendars, hidden, filter, first, count)
        : null;
    return AgendaLoadResult(
      access: access,
      revision: ++_revision,
      zone: zone,
      mode: mode,
      filter: filter,
      calendars: calendars,
      hidden: hidden,
      days: days,
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
      extra: SembleLayer.shared.directEntries(calendars, hidden),
    );
  }

  void dispose() {
    _disposed = true;
  }
}
