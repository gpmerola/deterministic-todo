import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agenda.dart';
import '../domain/task.dart' show CivilDate;
import 'agenda_service.dart';
import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

/// Web Agenda: reads the copy the phone mirrors to Supabase
/// (`agenda_snapshots`, `agenda_events`). Read-only; every view, the day
/// detail and search work as on the phone. Times are shown in the browser's
/// zone; all-day events keep their civil dates.
class WebAgendaService extends AgendaService {
  WebAgendaService(super.database, this.client);

  final SupabaseClient client;
  Map<String, Object?>? _snapshot;

  @override
  bool get canWrite => false;

  @override
  String? get mirrorLabel {
    final uploaded = DateTime.tryParse(
      _snapshot?['uploaded_at'] as String? ?? '',
    )?.toLocal();
    if (uploaded == null) return null;
    return 'Copia dal telefono · '
        '${DateFormat('d MMM HH:mm', 'it').format(uploaded)}';
  }

  Future<Map<String, Object?>?> _readSnapshot() async {
    if (client.auth.currentSession == null) return _snapshot = null;
    return _snapshot = await client
        .from('agenda_snapshots')
        .select()
        .maybeSingle();
  }

  @override
  Future<AgendaAccess> access() async {
    try {
      return await _readSnapshot() == null
          ? AgendaAccess.noMirror
          : AgendaAccess.granted;
    } catch (_) {
      return _snapshot == null ? AgendaAccess.noMirror : AgendaAccess.granted;
    }
  }

  @override
  Future<AgendaAccess> requestAccess() => access();

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<List<AgendaCalendar>> calendars() async {
    final rows = (_snapshot ?? await _readSnapshot())?['calendars'];
    return lastCalendars = [
      for (final row in rows is List ? rows : const [])
        if (row is Map)
          AgendaCalendar(
            id: row['key'] as String,
            name: row['name'] as String? ?? '',
            accountName: row['account'] as String? ?? '',
            colorHex: row['color'] as String?,
          ),
    ];
  }

  @override
  Future<String?> deviceZoneLabel() async {
    final id = browserTimeZoneId;
    if (id == null) return lastZoneLabel = null;
    return lastZoneLabel = zoneLabel(
      id,
      DateTime.now().timeZoneOffset.inSeconds,
    );
  }

  static AgendaSourceEvent fromRow(Map<String, Object?> row) {
    final keys = row['calendar_keys'];
    final allDay = row['all_day'] == true;
    return AgendaSourceEvent(
      instanceId: row['instance_key']! as String,
      calendarId: keys is List && keys.isNotEmpty ? keys.first as String : '',
      title: row['title'] as String? ?? '',
      start: allDay
          ? CivilDate.parse(row['start_date']! as String).asLocalDate
          : DateTime.parse(row['starts_at']! as String).toLocal(),
      end: allDay
          ? CivilDate.parse(row['end_date']! as String).asLocalDate
          : DateTime.parse(row['ends_at']! as String).toLocal(),
      allDay: allDay,
      location: row['location'] as String?,
      // Only the meeting link was mirrored; it is all findMeetingLink needs.
      url: row['meeting_url'] as String?,
      timeZone: row['time_zone'] as String?,
      eventZoneTimes: row['event_zone_times'] as String?,
      isOrganizer: row['is_organizer'] as bool? ?? true,
    );
  }

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async {
    if (calendarIds.isEmpty) return const [];
    final rows = await client
        .from('agenda_events')
        .select()
        .lt('starts_at', end.toUtc().toIso8601String())
        .gt('ends_at', start.toUtc().toIso8601String())
        .order('starts_at');
    final wanted = calendarIds.toSet();
    return [
      for (final row in rows)
        if (wanted.contains(fromRow(row).calendarId)) fromRow(row),
    ];
  }

  @override
  Future<List<AgendaEntry>> searchEvents(String text, DateTime now) async {
    final query = text.trim();
    if (query.length < 2 || await access() != AgendaAccess.granted) {
      return const [];
    }
    final escaped = query.replaceAll(RegExp(r'[%_\\]'), '');
    final rows = await client
        .from('agenda_events')
        .select()
        .ilike('title', '%$escaped%')
        .order('starts_at')
        .limit(200);
    final calendarList = lastCalendars ?? await calendars();
    return orderSearchResults(
      mergeAgendaEntries(
        events: [for (final row in rows) fromRow(row)],
        calendars: calendarList,
        hiddenCalendarIds: hiddenAgendaCalendars(
          calendarList,
          lastChoices ?? await calendarChoices(),
        ),
        filter: lastFilter ?? await filter(),
      ),
      now,
    );
  }

  /// Flags come from the phone (they are kept only there).
  @override
  Future<List<AgendaTaskItem>> tasks(CivilDate first, int days) async {
    final links = (_snapshot ?? await _readSnapshot())?['task_links'];
    return taskLinks.tasksBetween(
      first,
      days,
      withKeys: {
        for (final key in links is List ? links : const []) key as String,
      },
    );
  }

  @override
  Future<void> openEvent(String instanceId) =>
      throw UnsupportedError('Read-only web Agenda');

  @override
  Future<String> createEvent(AgendaEventDraft draft) =>
      throw UnsupportedError('Read-only web Agenda');

  @override
  Future<void> updateEvent(
    String instanceId,
    AgendaEventDraft draft, {
    bool series = false,
  }) => throw UnsupportedError('Read-only web Agenda');

  @override
  Future<void> deleteEvent(String instanceId, {bool series = false}) =>
      throw UnsupportedError('Read-only web Agenda');
}
