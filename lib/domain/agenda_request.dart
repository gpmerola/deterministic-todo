import 'package:intl/intl.dart';

import 'agenda.dart';
import 'task.dart' show CivilDate;

/// What the web Agenda asks the phone to do (table `agenda_requests`).
enum AgendaRequestKind { create, update, delete }

enum AgendaRequestStatus { pending, processing, done, failed }

/// A change typed on the web, applied by the phone that owns the calendars.
/// Times travel as UTC instants; all-day spans as civil dates, so the
/// browser's and the phone's zones cannot shift them.
final class AgendaRequest {
  const AgendaRequest({
    required this.id,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.instanceKey,
    this.series = false,
    this.payload = const {},
    this.error,
    this.completedAt,
  });

  final String id;
  final AgendaRequestKind kind;
  final AgendaRequestStatus status;
  final DateTime createdAt;

  /// Occurrence changed or deleted; null for create.
  final String? instanceKey;
  final bool series;
  final Map<String, Object?> payload;

  /// Short Italian reason when the phone could not apply it.
  final String? error;
  final DateTime? completedAt;

  bool get open =>
      status == AgendaRequestStatus.pending ||
      status == AgendaRequestStatus.processing;

  static AgendaRequest fromRow(Map<String, Object?> row) => AgendaRequest(
    id: row['id']! as String,
    kind: AgendaRequestKind.values.byName(row['kind']! as String),
    status: AgendaRequestStatus.values.byName(row['status']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
    instanceKey: row['instance_key'] as String?,
    series: row['series'] as bool? ?? false,
    payload: Map<String, Object?>.from(row['payload'] as Map? ?? const {}),
    error: row['error'] as String?,
    completedAt: DateTime.tryParse(row['completed_at'] as String? ?? ''),
  );

  /// The event fields carried by create/update, or null for delete and for
  /// a payload that cannot be read.
  AgendaEventDraft? get draft => draftFromAgendaPayload(payload);
}

/// Payload for a create or update typed on the web. Notes and repetition
/// travel only with a create: an edit keeps what the phone has.
Map<String, Object?> agendaRequestPayload(
  AgendaEventDraft draft, {
  required bool create,
}) => {
  'calendar': draft.calendarId,
  'title': draft.title.trim(),
  'all_day': draft.allDay,
  if (draft.allDay) ...{
    'start_date': CivilDate.fromDateTime(draft.start).toString(),
    'end_date': CivilDate.fromDateTime(draft.end).toString(),
  } else ...{
    'start': draft.start.toUtc().toIso8601String(),
    'end': draft.end.toUtc().toIso8601String(),
  },
  'location': _blankToNull(draft.location),
  if (create) 'notes': _blankToNull(draft.notes),
  if (create && draft.repeat != AgendaRepeat.none) 'repeat': draft.repeat.name,
  if (create && draft.repeat != AgendaRepeat.none && draft.repeatUntil != null)
    'repeat_until': draft.repeatUntil.toString(),
};

/// Reads [agendaRequestPayload] back into local time. Null when a field is
/// missing or malformed: the phone then rejects the request.
AgendaEventDraft? draftFromAgendaPayload(Map<String, Object?> payload) {
  try {
    final allDay = payload['all_day'] == true;
    final DateTime start;
    final DateTime end;
    if (allDay) {
      start = CivilDate.parse(payload['start_date']! as String).asLocalDate;
      end = CivilDate.parse(payload['end_date']! as String).asLocalDate;
    } else {
      start = DateTime.parse(payload['start']! as String).toLocal();
      end = DateTime.parse(payload['end']! as String).toLocal();
    }
    final repeat = payload['repeat'] as String?;
    final until = payload['repeat_until'] as String?;
    return AgendaEventDraft(
      calendarId: payload['calendar'] as String? ?? '',
      title: payload['title'] as String? ?? '',
      start: start,
      end: end,
      allDay: allDay,
      location: payload['location'] as String?,
      notes: payload['notes'] as String?,
      repeat: repeat == null
          ? AgendaRepeat.none
          : AgendaRepeat.values.byName(repeat),
      repeatUntil: until == null ? null : CivilDate.parse(until),
    );
  } on Object {
    return null;
  }
}

String? _blankToNull(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// "Nuovo evento: Visita · gio 8 ott 15:00" for the list of refused changes.
String agendaRequestLabel(AgendaRequest request) {
  final draft = request.draft;
  final title = (request.payload['title'] as String?)?.trim();
  final named = title == null || title.isEmpty ? 'evento' : '«$title»';
  final when = draft == null
      ? ''
      : ' · ${DateFormat(draft.allDay ? 'EEE d MMM' : 'EEE d MMM HH:mm', 'it').format(draft.start)}';
  return switch (request.kind) {
    AgendaRequestKind.create => 'Nuovo $named$when',
    AgendaRequestKind.update => 'Modifica di $named$when',
    AgendaRequestKind.delete => 'Eliminazione di $named',
  };
}
