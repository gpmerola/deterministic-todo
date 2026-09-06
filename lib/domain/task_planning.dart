import 'quick_add_parser.dart';
import 'task.dart';

/// UI planning policy shared by Android and Web.
///
/// Quick creation defaults to today. The editor can explicitly keep no date;
/// import and sync pipelines preserve the stored dates unchanged.
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

CivilDate? plannedEditorDate(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final value = input.trim();
  if (value.isEmpty) return null;
  try {
    return CivilDate.parse(value);
  } on FormatException {
    return CivilDate.fromDateTime(reference);
  }
}
