import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agenda.dart';
import '../domain/agenda_request.dart';
import '../domain/task.dart' show CivilDate;
import '../domain/text_fold.dart';
import 'agenda_service.dart';
import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

/// Marks web changes the phone has not applied yet.
const agendaPendingMarker = '⏳ ';

/// Web Agenda: reads the copy the phone mirrors to Supabase
/// (`agenda_snapshots`, `agenda_events`). Changes are queued in
/// `agenda_requests` and applied by the phone, the only one that can write
/// its calendars; until then they are shown with ⏳. Times are shown in the
/// browser's zone; all-day events keep their civil dates.
class WebAgendaService extends AgendaService {
  WebAgendaService(super.database, this.client);

  final SupabaseClient client;
  Map<String, Object?>? _snapshot;
  List<AgendaRequest> _requests = const [];

  @override
  bool get writesViaPhone => true;

  @override
  bool get canOpenInSystem => false;

  DateTime? get _uploadedAt =>
      DateTime.tryParse(_snapshot?['uploaded_at'] as String? ?? '');

  @override
  String? get mirrorLabel {
    final uploaded = _uploadedAt?.toLocal();
    if (uploaded == null) return null;
    final waiting = _overlay.length;
    return [
      'Copia dal telefono · '
          '${DateFormat('d MMM HH:mm', 'it').format(uploaded)}',
      if (waiting > 0) '$waiting in attesa',
    ].join(' · ');
  }

  @override
  List<AgendaRequest> get failedRequests => [
    for (final request in _requests)
      if (request.status == AgendaRequestStatus.failed) request,
  ];

  /// Requests whose effect the mirror does not show yet: still open, or
  /// applied after the last copy was uploaded.
  List<AgendaRequest> get _overlay {
    final uploaded = _uploadedAt;
    return [
      for (final request in _requests)
        if (request.open ||
            (request.status == AgendaRequestStatus.done &&
                uploaded != null &&
                (request.completedAt?.isAfter(uploaded) ?? false)))
          request,
    ];
  }

  Future<Map<String, Object?>?> _readSnapshot() async {
    if (client.auth.currentSession == null) return _snapshot = null;
    return _snapshot = await client
        .from('agenda_snapshots')
        .select()
        .maybeSingle();
  }

  Future<void> _readRequests() async {
    try {
      final rows = await client
          .from('agenda_requests')
          .select()
          .order('created_at')
          .limit(200);
      _requests = [for (final row in rows) AgendaRequest.fromRow(row)];
    } catch (_) {
      // Queue not migrated or offline: the mirror alone is still shown.
    }
  }

  @override
  Future<AgendaAccess> access() async {
    try {
      final snapshot = await _readSnapshot();
      if (snapshot == null) return AgendaAccess.noMirror;
      await _readRequests();
      return AgendaAccess.granted;
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
            // Copies from phones older than build 213 carry no flag.
            writable: row['writable'] as bool? ?? false,
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
      for (final event in applyAgendaRequests([
        for (final row in rows) fromRow(row),
      ], _overlay))
        if (wanted.contains(event.calendarId) &&
            event.start.isBefore(end) &&
            event.end.isAfter(start))
          event,
    ];
  }

  /// Accent-insensitive: Postgres narrows with `_` for letters that may
  /// carry an accent, the exact match is made here on folded titles.
  @override
  Future<List<AgendaEntry>> searchEvents(String text, DateTime now) async {
    final needle = foldForSearch(text.trim());
    if (needle.length < 2 || await access() != AgendaAccess.granted) {
      return const [];
    }
    final rows = await client
        .from('agenda_events')
        .select()
        .ilike('title', '%${likePrefilter(needle)}%')
        .order('starts_at')
        .limit(400);
    final calendarList = lastCalendars ?? await calendars();
    return orderSearchResults(
      mergeAgendaEntries(
        events: [
          for (final event in applyAgendaRequests([
            for (final row in rows) fromRow(row),
          ], _overlay))
            if (foldForSearch(event.title).contains(needle)) event,
        ],
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

  /// Form contents for an occurrence: the latest queued change if any,
  /// else the mirrored copy. Notes are not mirrored and stay on the phone.
  @override
  Future<AgendaEventDraft?> draftFor(String instanceId) async {
    final pending = _requestFor(instanceId);
    if (pending != null && pending.kind != AgendaRequestKind.delete) {
      final draft = pending.draft;
      if (draft != null) return draft;
    }
    final row = await client
        .from('agenda_events')
        .select()
        .eq('instance_key', instanceId)
        .maybeSingle();
    if (row == null) return null;
    final event = fromRow(row);
    return AgendaEventDraft(
      calendarId: event.calendarId,
      title: event.title,
      start: event.start,
      end: event.end,
      allDay: event.allDay,
      location: event.location,
    );
  }

  AgendaRequest? _requestFor(String instanceId) {
    final id = pendingRequestId(instanceId);
    if (id != null) return _requests.where((r) => r.id == id).firstOrNull;
    return _overlay.reversed
        .where((r) => r.instanceKey == instanceId)
        .firstOrNull;
  }

  @override
  Future<void> openEvent(String instanceId) =>
      throw UnsupportedError('No calendar app on the web');

  @override
  Future<String> createEvent(AgendaEventDraft draft) async {
    final row = await client
        .from('agenda_requests')
        .insert({
          'kind': AgendaRequestKind.create.name,
          'payload': agendaRequestPayload(draft, create: true),
        })
        .select()
        .single();
    await _readRequests();
    return row['id'] as String;
  }

  @override
  Future<void> updateEvent(
    String instanceId,
    AgendaEventDraft draft, {
    bool series = false,
  }) async {
    final queued = pendingRequestId(instanceId);
    if (queued != null) {
      // Not applied yet: change the queued creation itself.
      final original = _requests.where((r) => r.id == queued).firstOrNull;
      final changed = await client
          .from('agenda_requests')
          .update({
            'payload': agendaRequestPayload(
              AgendaEventDraft(
                calendarId: draft.calendarId,
                title: draft.title,
                start: draft.start,
                end: draft.end,
                allDay: draft.allDay,
                location: draft.location,
                notes: draft.notes,
                repeat: original?.draft?.repeat ?? AgendaRepeat.none,
                repeatUntil: original?.draft?.repeatUntil,
              ),
              create: true,
            ),
          })
          .eq('id', queued)
          .select('id');
      await _readRequests();
      if (changed.isEmpty) throw const AgendaQueueBusy();
      return;
    }
    await client.from('agenda_requests').insert({
      'kind': AgendaRequestKind.update.name,
      'instance_key': instanceId,
      'series': series,
      'payload': agendaRequestPayload(draft, create: false),
    });
    await _readRequests();
  }

  @override
  Future<void> deleteEvent(String instanceId, {bool series = false}) async {
    final queued = pendingRequestId(instanceId);
    if (queued != null) {
      // Withdraw a creation the phone has not picked up yet.
      final removed = await client
          .from('agenda_requests')
          .delete()
          .eq('id', queued)
          .select('id');
      await _readRequests();
      if (removed.isEmpty) throw const AgendaQueueBusy();
      return;
    }
    // The title only labels the request if the phone refuses it.
    final row = await client
        .from('agenda_events')
        .select('title')
        .eq('instance_key', instanceId)
        .maybeSingle();
    await client.from('agenda_requests').insert({
      'kind': AgendaRequestKind.delete.name,
      'instance_key': instanceId,
      'series': series,
      'payload': {'title': ?row?['title'] as String?},
    });
    await _readRequests();
  }

  @override
  Future<void> dismissRequest(String id) async {
    await client.from('agenda_requests').delete().eq('id', id);
    await _readRequests();
  }
}

/// The phone has already taken the request: it can no longer be changed.
final class AgendaQueueBusy implements Exception {
  const AgendaQueueBusy();
}

/// Instance id given to an event queued for creation.
String pendingInstanceId(String requestId) => 'req:$requestId';

String? pendingRequestId(String instanceId) =>
    instanceId.startsWith('req:') ? instanceId.substring(4) : null;

/// The mirrored events as they will be once the phone applies [requests]
/// (in queue order): deletions hidden, edits shown, creations added, all
/// changed ones marked with ⏳. A series change applies to every mirrored
/// occurrence of that series; times move only for the occurrence edited.
List<AgendaSourceEvent> applyAgendaRequests(
  List<AgendaSourceEvent> events,
  List<AgendaRequest> requests,
) {
  String seriesOf(String key) => key.split('@').first;
  var result = List.of(events);
  for (final request in requests) {
    final key = request.instanceKey;
    switch (request.kind) {
      case AgendaRequestKind.create:
        final draft = request.draft;
        if (draft == null) continue;
        result.add(
          AgendaSourceEvent(
            instanceId: pendingInstanceId(request.id),
            calendarId: draft.calendarId,
            title: '$agendaPendingMarker${draft.title}',
            start: draft.start,
            end: draft.end,
            allDay: draft.allDay,
            location: draft.location,
          ),
        );
      case AgendaRequestKind.delete:
        result = [
          for (final event in result)
            if (!(event.instanceId == key ||
                (request.series &&
                    key != null &&
                    event.instanceId.contains('@') &&
                    seriesOf(event.instanceId) == seriesOf(key))))
              event,
        ];
      case AgendaRequestKind.update:
        final draft = request.draft;
        if (draft == null || key == null) continue;
        result = [
          for (final event in result)
            if (event.instanceId == key)
              _edited(event, draft, times: true)
            else if (request.series &&
                event.instanceId.contains('@') &&
                seriesOf(event.instanceId) == seriesOf(key))
              _edited(event, draft, times: false)
            else
              event,
        ];
    }
  }
  return result;
}

AgendaSourceEvent _edited(
  AgendaSourceEvent event,
  AgendaEventDraft draft, {
  required bool times,
}) => AgendaSourceEvent(
  instanceId: event.instanceId,
  calendarId: event.calendarId,
  title: '$agendaPendingMarker${draft.title}',
  start: times ? draft.start : event.start,
  end: times ? draft.end : event.end,
  allDay: times ? draft.allDay : event.allDay,
  location: draft.location,
  url: event.url,
  timeZone: event.timeZone,
  isOrganizer: event.isOrganizer,
);
