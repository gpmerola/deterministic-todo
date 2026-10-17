import 'package:drift/drift.dart';

import '../data/local/database.dart';
import '../domain/task.dart';
import 'todoist_import_service.dart';

/// One compared quantity: what the export implies and what SQLite holds.
final class TodoistCheck {
  const TodoistCheck(this.label, this.expected, this.actual);
  final String label;
  final int expected;
  final int actual;
  bool get ok => expected == actual;
}

/// Read-only comparison of a Todoist export with the local database, for the
/// final migration ("Sostituisci") and for comparing Android with the browser
/// on the same file. Counts only: no title, note or ID ever enters [toText].
final class TodoistVerificationReport {
  const TodoistVerificationReport({
    required this.checks,
    required this.fieldMismatches,
    required this.appOnlyTasks,
  });

  final List<TodoistCheck> checks;

  /// Field → imported tasks whose local value differs from the export.
  final Map<String, int> fieldMismatches;

  /// Active tasks created in the app: untouched by Todoist, reported apart.
  final int appOnlyTasks;

  bool get ok =>
      checks.every((c) => c.ok) && fieldMismatches.values.every((n) => n == 0);

  String toText() {
    final lines = [
      ok
          ? 'Verifica Todoist: tutto corrisponde'
          : 'Verifica Todoist: differenze',
      for (final c in checks)
        '${c.ok ? '✓' : '✗'} ${c.label}: attesi ${c.expected}, trovati ${c.actual}',
      for (final e in fieldMismatches.entries)
        '${e.value == 0 ? '✓' : '✗'} ${e.key} diversi: ${e.value}',
      'Attività create nell’app (non Todoist, invariate): $appOnlyTasks',
    ];
    return lines.join('\n');
  }
}

bool _hasLink(String? text) =>
    text != null && RegExp(r'https?://').hasMatch(text);

Future<TodoistVerificationReport> verifyTodoistImport(
  AppDatabase db,
  TodoistImportPlan plan,
) async {
  final projects =
      await (db.select(db.projects)..where(
            (r) =>
                r.externalSource.equals('todoist') & r.isArchived.equals(false),
          ))
          .get();
  final sections =
      await (db.select(db.projectSections)..where(
            (r) =>
                r.externalSource.equals('todoist') & r.isArchived.equals(false),
          ))
          .get();
  final active =
      await (db.select(db.tasks)..where(
            (r) =>
                r.deletedAt.isNull() &
                r.completedAt.isNull() &
                r.status.equals(TaskStatus.completed.name).not(),
          ))
          .get();
  final imported = {
    for (final t in active.where((t) => t.externalSource == 'todoist')) t.id: t,
  };
  final appOnly = active.where((t) => t.externalSource != 'todoist').length;

  final projectIds = projects.map((p) => p.id).toSet();
  final sectionIds = sections.map((s) => s.id).toSet();
  final planProjects = plan.projects.map((p) => p.id).toSet();
  final planSections = plan.sections.map((s) => s.id).toSet();
  final planTasks = {for (final t in plan.tasks) t.id: t};

  final mismatches = <String, int>{
    'Titoli': 0,
    'Descrizioni': 0,
    'Priorità': 0,
    'Progetti delle attività': 0,
    'Sezioni delle attività': 0,
    'Date': 0,
    'Ricorrenze': 0,
  };
  void count(String key, bool differs) {
    if (differs) mismatches[key] = mismatches[key]! + 1;
  }

  for (final draft in plan.tasks) {
    final local = imported[draft.id];
    if (local == null) continue;
    count('Titoli', local.title != draft.title);
    count('Descrizioni', (local.notes ?? '') != (draft.notes ?? ''));
    count('Priorità', local.priority != draft.priority);
    count('Progetti delle attività', local.projectId != draft.projectId);
    count('Sezioni delle attività', local.sectionId != draft.sectionId);
    count('Date', local.showDate != draft.showDate);
    count('Ricorrenze', local.recurrence != draft.recurrence);
  }

  final matched = [
    for (final id in planTasks.keys)
      if (imported.containsKey(id)) imported[id]!,
  ];
  int priority(Iterable<int> values, int p) =>
      values.where((v) => v == p).length;
  return TodoistVerificationReport(
    checks: [
      TodoistCheck(
        'Progetti',
        planProjects.length,
        projectIds.intersection(planProjects).length,
      ),
      TodoistCheck(
        'Progetti Todoist in più',
        0,
        projectIds.difference(planProjects).length,
      ),
      TodoistCheck(
        'Sezioni',
        planSections.length,
        sectionIds.intersection(planSections).length,
      ),
      TodoistCheck(
        'Sezioni Todoist in più',
        0,
        sectionIds.difference(planSections).length,
      ),
      TodoistCheck('Attività attive', planTasks.length, matched.length),
      TodoistCheck(
        'Attività Todoist attive in più',
        0,
        imported.keys.where((id) => !planTasks.containsKey(id)).length,
      ),
      TodoistCheck(
        'Con data',
        plan.tasks.where((t) => t.showDate != null).length,
        matched.where((t) => t.showDate != null).length,
      ),
      TodoistCheck(
        'Ricorrenti',
        plan.tasks.where((t) => t.recurrence != null).length,
        matched.where((t) => t.recurrence != null).length,
      ),
      TodoistCheck(
        'Con descrizione',
        plan.tasks.where((t) => (t.notes ?? '').isNotEmpty).length,
        matched.where((t) => (t.notes ?? '').isNotEmpty).length,
      ),
      TodoistCheck(
        'Con link',
        plan.tasks.where((t) => _hasLink(t.title) || _hasLink(t.notes)).length,
        matched.where((t) => _hasLink(t.title) || _hasLink(t.notes)).length,
      ),
      for (var p = 4; p >= 1; p--)
        TodoistCheck(
          'Priorità Todoist $p',
          priority(plan.tasks.map((t) => t.priority), p),
          priority(matched.map((t) => t.priority), p),
        ),
    ],
    fieldMismatches: mismatches,
    appOnlyTasks: appOnly,
  );
}
