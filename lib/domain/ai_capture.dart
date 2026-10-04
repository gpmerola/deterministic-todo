import 'dart:convert';

import 'package:intl/intl.dart';

import 'task.dart';

/// Prefix on every task and event the assistant creates: visible in Todo,
/// on the Web and in Google/Outlook, and easy to find and strip later.
const aiMarker = '✨ ';

/// Footer appended to notes of created items, for the same reason.
const aiFooter = 'Creato con l\'assistente AI di Todo.';

String markAiTitle(String title) {
  final clean = title.trim();
  return clean.startsWith(aiMarker.trim()) ? clean : '$aiMarker$clean';
}

/// What the model may use, numbered so replies reference items by short ids
/// instead of copying names or UUIDs.
final class AiCaptureContext {
  const AiCaptureContext({
    required this.now,
    required this.zoneLabel,
    this.projects = const [],
    this.calendars = const [],
    this.defaultCalendarId,
    this.upcoming = const [],
  });

  /// Local wall-clock time on the phone.
  final DateTime now;
  final String? zoneLabel;
  final List<({String id, String name})> projects;

  /// Writable calendars shown in Agenda.
  final List<({String id, String name})> calendars;
  final String? defaultCalendarId;

  /// Events of the next days, so "before Thursday's meeting" resolves.
  final List<({String title, DateTime start, DateTime end, bool allDay})>
  upcoming;

  CivilDate get today => CivilDate.fromDateTime(now);
}

enum AiProposalKind { task, event }

/// One item suggested by the model, already validated against the context.
final class AiProposal {
  const AiProposal.task({
    required this.title,
    this.date,
    this.projectId,
    this.notes,
    this.relatedEvent,
  }) : kind = AiProposalKind.task,
       start = null,
       end = null,
       allDay = false,
       calendarId = null,
       location = null;

  const AiProposal.event({
    required this.title,
    required DateTime this.start,
    required DateTime this.end,
    required String this.calendarId,
    this.allDay = false,
    this.location,
    this.notes,
    this.relatedEvent,
  }) : kind = AiProposalKind.event,
       date = null,
       projectId = null;

  final AiProposalKind kind;
  final String title;

  /// Task date (tasks have no time of day).
  final CivilDate? date;
  final String? projectId;

  /// Event span; all-day ends are exclusive midnights.
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? calendarId;
  final String? location;
  final String? notes;

  /// "TNG Meeting · gio 8 ott 15:30" when tied to an upcoming event.
  final String? relatedEvent;

  /// Notes to store, with the link and the assistant footer.
  String storedNotes() => [
    if (notes != null && notes!.trim().isNotEmpty) notes!.trim(),
    if (relatedEvent != null) 'Collegata a: $relatedEvent',
    aiFooter,
  ].join('\n\n');
}

final class AiCaptureResult {
  const AiCaptureResult(this.items, {this.note, this.dropped = 0});
  final List<AiProposal> items;

  /// Short remark from the model (e.g. an ambiguity), shown as is.
  final String? note;

  /// Items discarded because invalid (bad dates, empty titles…).
  final int dropped;
}

/// System prompt: rules and the JSON shape (DeepSeek's JSON mode requires
/// the word "json" and an example). The no-invented-date rule was added
/// after a real test on build 207 dated "comprare latte" to tomorrow.
String aiCaptureSystemPrompt() => '''
You turn a short note written or dictated by the user (usually Italian) into
tasks for a to-do list and/or events for a calendar. Reply with json only.

Rules:
- A task has a date but never a time. Use a task for things to do ("preparare",
  "chiamare", "inviare", deadlines like "entro venerdì").
- An event has a start and end time (or is all-day). Use an event for
  appointments, meetings, visits, or anything with a clock time or a place.
- If the note gives no date or deadline, a task gets "date": null. Never
  invent a date.
- Resolve relative dates ("domani", "giovedì", "tra due settimane") from TODAY.
  Weeks start on Monday. A weekday name means the next such day (today counts
  only if the time has not passed).
- Default event duration: 60 minutes. Times are local, 24-hour.
- If the note refers to an upcoming event (e.g. "before Thursday's TNG meeting"),
  set "related" to its id (E1, E2…) and date the task relative to it (the
  working day before, unless the note says otherwise).
- Use a project only if one clearly matches (P1, P2…), else null. Use a
  calendar id (C1, C2…) only if the note names it, else null (the default).
- Keep titles short, in the user's language, without dates or times. Never
  invent people, places or details. Several items are allowed (max 10).
- If something is ambiguous, still propose your best reading and explain it
  in "note" (one short Italian sentence), otherwise "note" is null.

json format example:
{"items":[
 {"type":"task","title":"Preparare slide","date":"2026-10-07","project":"P2","related":"E3","notes":null},
 {"type":"event","title":"Visita","start":"2026-10-08T15:00","end":"2026-10-08T16:00","all_day":false,"calendar":null,"location":"Maudsley","notes":null,"related":null},
 {"type":"event","title":"Congresso","start":"2026-10-12","end":"2026-10-13","all_day":true,"calendar":"C2","location":null,"notes":null,"related":null}
],"note":null}
For all-day events "start" and "end" are dates and "end" is the last day.''';

/// User message: today, zone, numbered projects/calendars/events, the note.
String aiCaptureUserPrompt(AiCaptureContext context, String text) {
  final day = DateFormat('EEEE yyyy-MM-dd HH:mm', 'en');
  final when = DateFormat('EEE yyyy-MM-dd HH:mm', 'en');
  final buffer = StringBuffer()
    ..writeln('TODAY: ${day.format(context.now)}')
    ..writeln('TIME ZONE: ${context.zoneLabel ?? 'unknown'}')
    ..writeln('PROJECTS:');
  for (final (index, project) in context.projects.indexed) {
    buffer.writeln('P${index + 1}: ${project.name}');
  }
  buffer.writeln('CALENDARS:');
  for (final (index, calendar) in context.calendars.indexed) {
    final isDefault = calendar.id == context.defaultCalendarId
        ? ' (default)'
        : '';
    buffer.writeln('C${index + 1}: ${calendar.name}$isDefault');
  }
  buffer.writeln('UPCOMING EVENTS:');
  for (final (index, event) in context.upcoming.indexed) {
    final span = event.allDay
        ? '${DateFormat('EEE yyyy-MM-dd', 'en').format(event.start)} all-day'
        : '${when.format(event.start)}-${DateFormat.Hm().format(event.end)}';
    buffer.writeln('E${index + 1}: $span | ${event.title}');
  }
  buffer
    ..writeln('NOTE:')
    ..write(text.trim());
  return buffer.toString();
}

/// Parses and validates the model's json against [context]. Invalid items
/// are dropped and counted, never guessed.
AiCaptureResult parseAiCapture(String raw, AiCaptureContext context) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('Risposta senza json');
  }
  final decoded = jsonDecode(raw.substring(start, end + 1));
  if (decoded is! Map) throw const FormatException('json non valido');
  final items = decoded['items'];
  if (items is! List) throw const FormatException('Elenco mancante');

  T? byRef<T>(Object? ref, String prefix, List<T> list) {
    if (ref is! String || !ref.startsWith(prefix)) return null;
    final index = int.tryParse(ref.substring(prefix.length));
    if (index == null || index < 1 || index > list.length) return null;
    return list[index - 1];
  }

  final earliest = context.today.addDays(-1);
  final latest = context.today.addDays(3 * 366);
  bool inRange(CivilDate date) =>
      date.compareTo(earliest) >= 0 && date.compareTo(latest) <= 0;

  final result = <AiProposal>[];
  var dropped = 0;
  for (final item in items.take(10)) {
    try {
      if (item is! Map) throw const FormatException('item');
      final title = (item['title'] as String? ?? '').trim();
      if (title.isEmpty || title.length > 200) {
        throw const FormatException('title');
      }
      final related = byRef(item['related'], 'E', context.upcoming);
      final relatedLabel = related == null
          ? null
          : '${related.title} · '
                '${DateFormat(related.allDay ? 'EEE d MMM' : 'EEE d MMM HH:mm', 'it').format(related.start)}';
      final notes = item['notes'] as String?;
      switch (item['type']) {
        case 'task':
          final rawDate = item['date'] as String?;
          final date = rawDate == null ? null : CivilDate.parse(rawDate);
          if (date != null && !inRange(date)) {
            throw const FormatException('date');
          }
          result.add(
            AiProposal.task(
              title: title,
              date: date,
              projectId: byRef(item['project'], 'P', context.projects)?.id,
              notes: notes,
              relatedEvent: relatedLabel,
            ),
          );
        case 'event':
          final calendarId =
              byRef(item['calendar'], 'C', context.calendars)?.id ??
              context.defaultCalendarId;
          if (calendarId == null) throw const FormatException('calendar');
          final allDay = item['all_day'] == true;
          final DateTime from;
          final DateTime to;
          if (allDay) {
            final first = CivilDate.parse(
              (item['start'] as String).substring(0, 10),
            );
            final rawEnd = item['end'] as String?;
            final last = rawEnd == null
                ? first
                : CivilDate.parse(rawEnd.substring(0, 10));
            if (last.compareTo(first) < 0) throw const FormatException('end');
            from = first.asLocalDate;
            to = last.addDays(1).asLocalDate;
          } else {
            from = DateTime.parse(item['start'] as String);
            final rawEnd = item['end'] as String?;
            to = rawEnd == null
                ? from.add(const Duration(minutes: 60))
                : DateTime.parse(rawEnd);
            if (!to.isAfter(from)) throw const FormatException('end');
          }
          if (!inRange(CivilDate.fromDateTime(from))) {
            throw const FormatException('date');
          }
          result.add(
            AiProposal.event(
              title: title,
              start: from,
              end: to,
              allDay: allDay,
              calendarId: calendarId,
              location: (item['location'] as String?)?.trim().isEmpty ?? true
                  ? null
                  : (item['location'] as String).trim(),
              notes: notes,
              relatedEvent: relatedLabel,
            ),
          );
        default:
          throw const FormatException('type');
      }
    } on Object {
      dropped++;
    }
  }
  final note = decoded['note'];
  return AiCaptureResult(
    result,
    note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    dropped: dropped + (items.length > 10 ? items.length - 10 : 0),
  );
}
