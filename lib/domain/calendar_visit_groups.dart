import 'agenda.dart';
import 'task.dart';

/// A presentation item only: the original events and their IDs are retained.
final class CalendarVisitItem {
  CalendarVisitItem(Iterable<AgendaEntry> entries)
    : entries = List.unmodifiable(entries);

  final List<AgendaEntry> entries;
  bool get grouped => entries.length >= 3;
  AgendaEntry get first => entries.first;
  DateTime get end => entries.last.end;
}

// Conservative labels, not patient names or fuzzy title similarity.
final _visitLabel = RegExp(
  r'\b(visita|visite|consulto|consultazione|consultation|appointment|assessment)\b|\bfollow[\s‐‑–-]?up\b',
  caseSensitive: false,
);

List<CalendarVisitItem> calendarVisitItems(
  List<AgendaEntry> entries,
  CivilDate day,
) {
  final timed = entries.where((e) => !e.allDay && !e.isTask).toList()
    ..sort((a, b) {
      final start = a.start.compareTo(b.start);
      if (start != 0) return start;
      final end = a.end.compareTo(b.end);
      return end != 0 ? end : a.instanceId.compareTo(b.instanceId);
    });
  final overlapping = <AgendaEntry>{};
  AgendaEntry? furthest;
  for (final entry in timed) {
    if (furthest != null && entry.start.isBefore(furthest.end)) {
      overlapping.addAll([entry, furthest]);
    }
    if (furthest == null || entry.end.isAfter(furthest.end)) furthest = entry;
  }
  bool eligible(AgendaEntry e) =>
      !e.allDay &&
      !e.isTask &&
      !e.unanswered &&
      !e.title.startsWith('In attesa · ') &&
      e.calendarIds.isNotEmpty &&
      !overlapping.contains(e) &&
      e.end.isAfter(e.start) &&
      CivilDate(e.start.year, e.start.month, e.start.day) == day &&
      CivilDate(e.end.year, e.end.month, e.end.day) == day &&
      _visitLabel.hasMatch(e.title);
  bool sameCalendars(AgendaEntry a, AgendaEntry b) =>
      a.calendarIds.length == b.calendarIds.length &&
      List.generate(
        a.calendarIds.length,
        (i) => i,
      ).every((i) => a.calendarIds[i] == b.calendarIds[i]);
  final result = <CalendarVisitItem>[];
  var run = <AgendaEntry>[];
  void flush() {
    if (run.length >= 3) {
      result.add(CalendarVisitItem(run));
    } else {
      result.addAll(run.map((e) => CalendarVisitItem([e])));
    }
    run = [];
  }

  for (final entry in entries) {
    if (!eligible(entry)) {
      flush();
      result.add(CalendarVisitItem([entry]));
      continue;
    }
    if (run.isNotEmpty &&
        (entry.start.isBefore(run.last.end) ||
            entry.start.difference(run.last.end) >
                const Duration(minutes: 15) ||
            !sameCalendars(run.last, entry))) {
      flush();
    }
    run.add(entry);
  }
  flush();
  return result;
}
