import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agenda.dart';
import '../domain/agenda_request.dart';
import 'agenda_service.dart';

/// Why the phone refused a request; shown on the web as is.
final class AgendaRequestRejected implements Exception {
  const AgendaRequestRejected(this.message);
  final String message;
}

/// Phone side of web edits: claims the queued requests once, writes them
/// into the phone calendars like an edit made in Agenda, and reports the
/// result. Runs on app start/resume and in the background job; never polls.
class AgendaRequestProcessor {
  AgendaRequestProcessor({
    required this.service,
    required this.client,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Resume can fire often; one check per minute is enough.
  static const minInterval = Duration(minutes: 1);

  final AgendaService service;
  final SupabaseClient client;
  final DateTime Function() _now;
  DateTime? _last;
  bool _busy = false;

  Future<int> processIfStale() async {
    final last = _last;
    if (last != null && _now().difference(last) < minInterval) return 0;
    return process();
  }

  /// Applies the pending requests; returns how many were handled. Failures
  /// are reported per request and never logged (they carry event titles).
  Future<int> process() async {
    if (_busy || client.auth.currentSession == null) return 0;
    _busy = true;
    try {
      if (await service.access() != AgendaAccess.granted) return 0;
      _last = _now();
      final rows = await client.rpc<List<dynamic>>(
        'claim_agenda_requests_v1',
        params: {'max_count': 20},
      );
      final requests = [
        for (final row in rows)
          AgendaRequest.fromRow(Map<String, Object?>.from(row as Map)),
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final request in requests) {
        String? failure;
        try {
          await apply(request);
        } on AgendaRequestRejected catch (rejected) {
          failure = rejected.message;
        } catch (_) {
          failure = 'Il telefono non è riuscito ad applicarla.';
        }
        await client.rpc<Object?>(
          'complete_agenda_request_v1',
          params: {
            'request_id': request.id,
            'succeeded': failure == null,
            'message': failure,
          },
        );
      }
      return requests.length;
    } catch (_) {
      // Offline or not migrated yet: the next start retries.
      return 0;
    } finally {
      _busy = false;
    }
  }

  /// Writes one request into the phone calendars.
  Future<void> apply(AgendaRequest request) async {
    switch (request.kind) {
      case AgendaRequestKind.create:
        final draft = _validDraft(request);
        await _requireWritable(draft.calendarId);
        await service.createEvent(draft);
      case AgendaRequestKind.update:
        final changed = _validDraft(request);
        final existing = await service.draftFor(request.instanceKey!);
        if (existing == null) {
          throw const AgendaRequestRejected(
            'L\'evento non c\'è più sul telefono.',
          );
        }
        await _requireWritable(existing.calendarId);
        // The phone keeps its calendar, notes and series rule.
        await service.updateEvent(
          request.instanceKey!,
          AgendaEventDraft(
            calendarId: existing.calendarId,
            title: changed.title,
            start: changed.start,
            end: changed.end,
            allDay: changed.allDay,
            location: changed.location,
            notes: existing.notes,
          ),
          series: request.series,
        );
      case AgendaRequestKind.delete:
        final existing = await service.draftFor(request.instanceKey!);
        // Already gone: the wish is fulfilled.
        if (existing == null) return;
        await _requireWritable(existing.calendarId);
        await service.deleteEvent(request.instanceKey!, series: request.series);
    }
  }

  AgendaEventDraft _validDraft(AgendaRequest request) {
    final draft = request.draft;
    if (draft == null) {
      throw const AgendaRequestRejected('Richiesta non leggibile.');
    }
    final problem = draft.problem;
    if (problem != null) throw AgendaRequestRejected(problem);
    return draft;
  }

  Future<void> _requireWritable(String calendarId) async {
    final calendars = service.lastCalendars ?? await service.calendars();
    final calendar = calendars.where((c) => c.id == calendarId).firstOrNull;
    if (calendar == null) {
      throw const AgendaRequestRejected('Calendario non più sul telefono.');
    }
    if (!calendar.writable) {
      throw const AgendaRequestRejected('Calendario in sola lettura.');
    }
  }
}
