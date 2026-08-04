import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../domain/quick_add_parser.dart';

class TodoistImportResult {
  const TodoistImportResult({
    required this.addedProjects,
    required this.addedSections,
    required this.addedTasks,
  });

  final int addedProjects;
  final int addedSections;
  final int addedTasks;
}

class TodoistProjectDraft {
  const TodoistProjectDraft({
    required this.id,
    required this.externalId,
    required this.name,
    required this.position,
    this.color,
    this.parentId,
    this.isFavorite = false,
  });
  final String id;
  final String externalId;
  final String name;
  final int position;
  final String? color;
  final String? parentId;
  final bool isFavorite;
}

class TodoistSectionDraft {
  const TodoistSectionDraft({
    required this.id,
    required this.externalId,
    required this.projectId,
    required this.name,
    required this.position,
  });
  final String id;
  final String externalId;
  final String projectId;
  final String name;
  final int position;
}

class TodoistTaskDraft {
  const TodoistTaskDraft({
    required this.id,
    required this.externalId,
    required this.title,
    required this.priority,
    required this.position,
    this.notes,
    this.projectId,
    this.sectionId,
    this.showDate,
    this.timeMinutes,
    this.timeZone,
    this.recurrence,
  });
  final String id;
  final String externalId;
  final String title;
  final String? notes;
  final int priority;
  final int position;
  final String? projectId;
  final String? sectionId;
  final String? showDate;
  final int? timeMinutes;
  final String? timeZone;
  final String? recurrence;
}

class TodoistImportPlan {
  const TodoistImportPlan({
    required this.preview,
    required this.projects,
    required this.sections,
    required this.tasks,
  });
  final TodoistImportPreview preview;
  final List<TodoistProjectDraft> projects;
  final List<TodoistSectionDraft> sections;
  final List<TodoistTaskDraft> tasks;
}

class TodoistImportPreview {
  const TodoistImportPreview({
    required this.projects,
    required this.sections,
    required this.activeTasks,
    required this.scheduledTasks,
    required this.recurringTasks,
    required this.unsupportedRecurrences,
    required this.priorityCounts,
  });

  final int projects;
  final int sections;
  final int activeTasks;
  final int scheduledTasks;
  final int recurringTasks;
  final List<String> unsupportedRecurrences;
  final Map<int, int> priorityCounts;

  bool get canImport => unsupportedRecurrences.isEmpty;
}

/// Legge un export Sync Todoist senza scrivere alcun dato. L'importatore usa
/// questa anteprima come gate: nessun formato ambiguo passa silenziosamente.
class TodoistImportService {
  const TodoistImportService();

  static const _uuid = Uuid();

  TodoistImportPreview preview(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Export Todoist non valido');
    }
    final projects = _list(decoded, 'projects');
    final sections = _list(decoded, 'sections');
    final items = _list(decoded, 'items');
    final active = items.where((item) {
      return item['is_deleted'] != true && item['checked'] != true;
    }).toList();
    final priorityCounts = <int, int>{};
    var scheduled = 0;
    var recurring = 0;
    final unsupported = <String>{};
    for (final item in active) {
      final priority = item['priority'];
      if (priority is! int || priority < 1 || priority > 4) {
        throw const FormatException('Priorità Todoist non valida');
      }
      priorityCounts.update(priority, (count) => count + 1, ifAbsent: () => 1);
      final due = item['due'];
      if (due == null) continue;
      if (due is! Map<String, dynamic> || due['date'] is! String) {
        throw const FormatException('Data Todoist non valida');
      }
      scheduled++;
      if (due['is_recurring'] == true) {
        recurring++;
        final expression = (due['string'] as String? ?? '').trim();
        if (!_isSupportedRecurrence(expression)) unsupported.add(expression);
      }
    }
    return TodoistImportPreview(
      projects: projects.where((row) => row['is_deleted'] != true).length,
      sections: sections.where((row) => row['is_deleted'] != true).length,
      activeTasks: active.length,
      scheduledTasks: scheduled,
      recurringTasks: recurring,
      unsupportedRecurrences: unsupported.toList()..sort(),
      priorityCounts: priorityCounts,
    );
  }

  TodoistImportPlan plan(String source) {
    final report = preview(source);
    if (!report.canImport) {
      throw FormatException(
        'Ricorrenze Todoist da verificare: '
        '${report.unsupportedRecurrences.join(', ')}',
      );
    }
    final root = (jsonDecode(source) as Map).cast<String, dynamic>();
    final rawProjects = _list(
      root,
      'projects',
    ).where((row) => row['is_deleted'] != true).toList();
    final projectIds = <String, String>{
      for (final row in rawProjects)
        row['id'] as String: _externalUuid('project', row['id'] as String),
    };
    final projects = rawProjects.map((row) {
      final externalId = row['id'] as String;
      final parentExternal = row['parent_id'] as String?;
      return TodoistProjectDraft(
        id: projectIds[externalId]!,
        externalId: externalId,
        name: _requiredText(row, 'name'),
        position: row['child_order'] as int? ?? 0,
        color: row['color'] as String?,
        parentId: parentExternal == null ? null : projectIds[parentExternal],
        isFavorite: row['is_favorite'] == true,
      );
    }).toList();

    final rawSections = _list(
      root,
      'sections',
    ).where((row) => row['is_deleted'] != true).toList();
    final sectionIds = <String, String>{};
    final sections = <TodoistSectionDraft>[];
    for (final row in rawSections) {
      final externalId = row['id'] as String;
      final projectExternal = row['project_id'] as String;
      final projectId = projectIds[projectExternal];
      if (projectId == null) {
        throw const FormatException('Sezione Todoist senza progetto');
      }
      final id = _externalUuid('section', externalId);
      sectionIds[externalId] = id;
      sections.add(
        TodoistSectionDraft(
          id: id,
          externalId: externalId,
          projectId: projectId,
          name: _requiredText(row, 'name'),
          position: row['section_order'] as int? ?? 0,
        ),
      );
    }

    final tasks = <TodoistTaskDraft>[];
    for (final row in _list(root, 'items')) {
      if (row['is_deleted'] == true || row['checked'] == true) continue;
      final externalId = row['id'] as String;
      final due = row['due'] as Map<String, dynamic>?;
      String? showDate;
      int? timeMinutes;
      String? timeZone;
      String? recurrence;
      if (due != null) {
        final rawDate = due['date'] as String;
        final instant = DateTime.parse(rawDate);
        showDate = rawDate.substring(0, 10);
        if (rawDate.contains('T')) {
          timeMinutes = instant.hour * 60 + instant.minute;
        }
        timeZone = due['timezone'] as String?;
        if (due['is_recurring'] == true) {
          final expression = (due['string'] as String).trim();
          final parserExpression =
              RegExp(
                r'^ogni\s+[0-3]?\d$',
                caseSensitive: false,
              ).hasMatch(expression)
              ? '$expression del mese'
              : expression;
          recurrence = const QuickAddParser()
              .parse(
                'Attività $parserExpression',
                now: DateTime.parse(showDate),
              )
              .recurrence;
          if (recurrence == null) {
            throw FormatException(
              'Ricorrenza Todoist non mappata: ${due['string']}',
            );
          }
        }
      }
      final projectExternal = row['project_id'] as String?;
      final sectionExternal = row['section_id'] as String?;
      tasks.add(
        TodoistTaskDraft(
          id: _externalUuid('task', externalId),
          externalId: externalId,
          title: _requiredText(row, 'content'),
          notes: (row['description'] as String?)?.trim().isEmpty == true
              ? null
              : row['description'] as String?,
          priority: row['priority'] as int,
          position: row['child_order'] as int? ?? 0,
          projectId: projectExternal == null
              ? null
              : projectIds[projectExternal],
          sectionId: sectionExternal == null
              ? null
              : sectionIds[sectionExternal],
          showDate: showDate,
          timeMinutes: timeMinutes,
          timeZone: timeZone,
          recurrence: recurrence,
        ),
      );
    }
    return TodoistImportPlan(
      preview: report,
      projects: projects,
      sections: sections,
      tasks: tasks,
    );
  }

  /// Applica il piano in un'unica transazione. Gli UUID deterministici e gli
  /// indici external_source/external_id rendono sicuro ripetere lo stesso import.
  Future<TodoistImportResult> importPlan({
    required TodoistImportPlan plan,
    required AppDatabase db,
    required String deviceId,
  }) => db.transaction(() async {
    var addedProjects = 0;
    var addedSections = 0;
    var addedTasks = 0;
    final now = DateTime.now();
    final timestamp = now.toUtc().millisecondsSinceEpoch;
    final today = _dateOnly(now);

    for (final draft in plan.projects) {
      final existing = await (db.select(
        db.projects,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: draft.id,
              name: draft.name,
              position: draft.position * 1024,
              deviceId: deviceId,
              color: Value(draft.color),
              parentId: Value(draft.parentId),
              isFavorite: Value(draft.isFavorite),
              externalSource: const Value('todoist'),
              externalId: Value(draft.externalId),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      addedProjects++;
    }

    for (final draft in plan.sections) {
      final existing = await (db.select(
        db.projectSections,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.projectSections)
          .insert(
            ProjectSectionsCompanion.insert(
              id: draft.id,
              projectId: draft.projectId,
              name: draft.name,
              position: draft.position * 1024,
              deviceId: deviceId,
              externalSource: const Value('todoist'),
              externalId: Value(draft.externalId),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      addedSections++;
    }

    for (final draft in plan.tasks) {
      final existing = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      if (existing != null) continue;
      final status = draft.showDate == null
          ? 'inbox'
          : draft.showDate!.compareTo(today) <= 0
          ? 'available'
          : 'scheduled';
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: draft.id,
              title: draft.title,
              status: status,
              position: draft.position * 1024,
              createdAt: timestamp,
              updatedAt: timestamp,
              deviceId: deviceId,
              notes: Value(draft.notes),
              showDate: Value(draft.showDate),
              timeMinutes: Value(draft.timeMinutes),
              timeZone: Value(draft.timeZone),
              priority: Value(draft.priority),
              projectId: Value(draft.projectId),
              sectionId: Value(draft.sectionId),
              externalSource: const Value('todoist'),
              externalId: Value(draft.externalId),
              recurrence: Value(draft.recurrence),
              seriesId: Value(draft.recurrence == null ? null : draft.id),
              occurrenceKey: Value(
                draft.recurrence == null ? null : draft.showDate,
              ),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      addedTasks++;
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              operationId: _uuid.v4(),
              entityId: draft.id,
              operation: 'upsert',
              payload: jsonEncode({'id': draft.id, 'version': 1}),
              createdAt: timestamp,
            ),
          );
    }

    return TodoistImportResult(
      addedProjects: addedProjects,
      addedSections: addedSections,
      addedTasks: addedTasks,
    );
  });

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _externalUuid(String type, String externalId) =>
      _uuid.v5(Namespace.url.value, 'todoist:$type:$externalId');

  String _requiredText(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Campo Todoist $key non valido');
    }
    return value.trim();
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> root, String key) {
    final value = root[key];
    if (value is! List) throw FormatException('Campo Todoist $key mancante');
    return value.map((row) {
      if (row is! Map) throw FormatException('Record Todoist $key non valido');
      return row.cast<String, dynamic>();
    }).toList();
  }

  bool _isSupportedRecurrence(String value) => RegExp(
    r'^ogni\s+(?:(?:\d+\s+)?(?:giorno|giorni|settimana|settimane|mese|mesi|anno|anni)|(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)|(?:primo|secondo|terzo|quarto|quinto)\s+(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?|[0-3]?\d(?:\s+del\s+mese|\s+(?:gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre))?)$',
    caseSensitive: false,
  ).hasMatch(value);
}
