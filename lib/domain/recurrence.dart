import 'task.dart';

List<CivilDate> calendarOccurrences({
  required CivilDate anchor,
  required CivilDate through,
  required RecurrenceRule rule,
}) {
  if (rule.type != RecurrenceType.calendar) {
    throw ArgumentError('La regola deve essere da calendario');
  }
  final result = <CivilDate>[];
  var current = anchor;
  while (current.compareTo(through) <= 0) {
    result.add(current);
    current = nextOccurrence(anchor, current, rule);
  }
  return result;
}

CivilDate afterCompletionOccurrence({
  required CivilDate completedOn,
  required RecurrenceRule rule,
}) {
  if (rule.type != RecurrenceType.afterCompletion) {
    throw ArgumentError('La regola deve essere dal completamento');
  }
  return nextOccurrence(completedOn, completedOn, rule);
}
