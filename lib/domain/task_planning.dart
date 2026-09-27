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

/// Planning of an open task is derived from its civil date alone.
///
/// `status` only distinguishes completed and waiting items: `inbox`,
/// `available` and `scheduled` are equivalent open values. They are still
/// written, projected from the date at write time, because older clients
/// filter on them. A civil-day transition changes visibility, never the
/// persisted task version. View membership itself is defined once, in SQL,
/// by `TaskRepository.watchView`.
TaskStatus legacyOpenStatus(String? showDate, CivilDate today) =>
    showDate == null
    ? TaskStatus.inbox
    : showDate.compareTo(today.toString()) <= 0
    ? TaskStatus.available
    : TaskStatus.scheduled;

bool isOpenStatus(String status) =>
    status != TaskStatus.completed.name && status != TaskStatus.waiting.name;
