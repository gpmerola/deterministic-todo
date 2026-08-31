import 'quick_add_parser.dart';
import 'task.dart';

/// UI planning policy shared by Android and Web.
///
/// A missing or invalid explicit date means today. Import and sync pipelines do
/// not use this policy, so historical null dates remain untouched.
QuickTaskDraft parsePlannedQuickTask(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = CivilDate.fromDateTime(reference);
  try {
    final parsed = const QuickAddParser().parse(input, now: reference);
    return QuickTaskDraft(
      title: parsed.title,
      showDate: parsed.showDate ?? today,
      recurrence: parsed.recurrence,
    );
  } on FormatException {
    return QuickTaskDraft(title: input.trim(), showDate: today);
  }
}

CivilDate plannedDateOrToday(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final value = input.trim();
  if (value.isEmpty) return CivilDate.fromDateTime(reference);
  try {
    return CivilDate.parse(value);
  } on FormatException {
    return CivilDate.fromDateTime(reference);
  }
}
