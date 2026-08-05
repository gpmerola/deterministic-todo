import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../domain/link_syntax.dart';
import '../domain/quick_add_parser.dart';

class TodoistImportResult {
  const TodoistImportResult({
    required this.addedProjects,
    required this.addedSections,
    required this.addedTasks,
    this.updatedTasks = 0,
    this.removedTasks = 0,
  });

  final int addedProjects;
  final int addedSections;
  final int addedTasks;
  final int updatedTasks;
  final int removedTasks;
}

enum TodoistImportMode { incremental, replace }

class TodoistProjectDraft {
  const TodoistProjectDraft({
    required this.id,
    required this.externalId,
    required this.name,
    required this.position,
    this.color,
    this.parentId,
    this.isFavorite = false,
    this.updatedAt,
    this.viewStyle,
  });
  final String id;
  final String externalId;
  final String name;
  final int position;
  final String? color;
  final String? parentId;
  final bool isFavorite;
  final String? updatedAt;
  final String? viewStyle;
}

class TodoistSectionDraft {
  const TodoistSectionDraft({
    required this.id,
    required this.externalId,
    required this.projectId,
    required this.name,
    required this.position,
    this.updatedAt,
  });
  final String id;
  final String externalId;
  final String projectId;
  final String name;
  final int position;
  final String? updatedAt;
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
    this.recurrence,
    this.updatedAt,
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
  final String? recurrence;
  final String? updatedAt;
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
        updatedAt: row['updated_at'] as String?,
        viewStyle: row['view_style'] as String?,
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
          updatedAt: row['updated_at'] as String?,
        ),
      );
    }

    final tasks = <TodoistTaskDraft>[];
    for (final row in _list(root, 'items')) {
      if (row['is_deleted'] == true || row['checked'] == true) continue;
      final externalId = row['id'] as String;
      final due = row['due'] as Map<String, dynamic>?;
      String? showDate;
      String? recurrence;
      if (due != null) {
        final rawDate = due['date'] as String;
        showDate = rawDate.substring(0, 10);
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
          title: linkifyPlainUrls(_requiredText(row, 'content')),
          notes: _optionalLinkedText(row['description']),
          priority: row['priority'] as int,
          position: row['child_order'] as int? ?? 0,
          projectId: projectExternal == null
              ? null
              : projectIds[projectExternal],
          sectionId: sectionExternal == null
              ? null
              : sectionIds[sectionExternal],
          showDate: showDate,
          recurrence: recurrence,
          updatedAt: row['updated_at'] as String?,
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
    TodoistImportMode mode = TodoistImportMode.incremental,
  }) => db.transaction(() async {
    var addedProjects = 0;
    var addedSections = 0;
    var addedTasks = 0;
    var updatedTasks = 0;
    var removedTasks = 0;
    final now = DateTime.now();
    final timestamp = now.toUtc().microsecondsSinceEpoch;
    final today = _dateOnly(now);
    final importedProjectIds = plan.projects.map((item) => item.id).toSet();
    final importedSectionIds = plan.sections.map((item) => item.id).toSet();
    final importedTaskIds = plan.tasks.map((item) => item.id).toSet();

    for (final draft in plan.projects) {
      final existing = await (db.select(
        db.projects,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      final changed =
          mode == TodoistImportMode.replace ||
          (draft.updatedAt != null &&
              await _checkpoint(db, 'project', draft.externalId) !=
                  draft.updatedAt);
      if (existing != null) {
        if (changed) {
          await (db.update(
            db.projects,
          )..where((row) => row.id.equals(draft.id))).write(
            ProjectsCompanion(
              name: Value(draft.name),
              position: Value(draft.position * 1024),
              color: Value(draft.color),
              parentId: Value(draft.parentId),
              isFavorite: Value(draft.isFavorite),
              isArchived: const Value(false),
              logicalVersion: Value(existing.logicalVersion + 1),
              deviceId: Value(deviceId),
            ),
          );
        }
        await _saveCheckpoint(db, 'project', draft.externalId, draft.updatedAt);
        if (changed && draft.viewStyle != null) {
          await _saveSetting(db, 'project_view:${draft.id}', draft.viewStyle!);
        }
        continue;
      }
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
      await _saveCheckpoint(db, 'project', draft.externalId, draft.updatedAt);
      if (draft.viewStyle != null) {
        await _saveSetting(db, 'project_view:${draft.id}', draft.viewStyle!);
      }
    }

    for (final draft in plan.sections) {
      final existing = await (db.select(
        db.projectSections,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      final changed =
          mode == TodoistImportMode.replace ||
          (draft.updatedAt != null &&
              await _checkpoint(db, 'section', draft.externalId) !=
                  draft.updatedAt);
      if (existing != null) {
        if (changed) {
          await (db.update(
            db.projectSections,
          )..where((row) => row.id.equals(draft.id))).write(
            ProjectSectionsCompanion(
              projectId: Value(draft.projectId),
              name: Value(draft.name),
              position: Value(draft.position * 1024),
              isArchived: const Value(false),
              logicalVersion: Value(existing.logicalVersion + 1),
              deviceId: Value(deviceId),
            ),
          );
        }
        await _saveCheckpoint(db, 'section', draft.externalId, draft.updatedAt);
        continue;
      }
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
      await _saveCheckpoint(db, 'section', draft.externalId, draft.updatedAt);
    }

    for (final draft in plan.tasks) {
      final existing = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
      final status = draft.showDate == null
          ? 'inbox'
          : draft.showDate!.compareTo(today) <= 0
          ? 'available'
          : 'scheduled';
      final changed =
          mode == TodoistImportMode.replace ||
          (draft.updatedAt != null &&
              await _checkpoint(db, 'task', draft.externalId) !=
                  draft.updatedAt);
      if (existing != null) {
        if (changed) {
          final version = existing.logicalVersion + 1;
          await (db.update(
            db.tasks,
          )..where((row) => row.id.equals(draft.id))).write(
            TasksCompanion(
              title: Value(draft.title),
              notes: Value(draft.notes),
              showDate: Value(draft.showDate),
              timeMinutes: const Value(null),
              timeZone: const Value(null),
              priority: Value(draft.priority),
              projectId: Value(draft.projectId),
              sectionId: Value(draft.sectionId),
              position: Value(draft.position * 1024),
              recurrence: Value(draft.recurrence),
              seriesId: Value(
                draft.recurrence == null ? null : existing.seriesId ?? draft.id,
              ),
              occurrenceKey: Value(
                draft.recurrence == null ? null : draft.showDate,
              ),
              status: mode == TodoistImportMode.replace
                  ? Value(status)
                  : const Value.absent(),
              completedAt: mode == TodoistImportMode.replace
                  ? const Value(null)
                  : const Value.absent(),
              deletedAt: mode == TodoistImportMode.replace
                  ? const Value(null)
                  : const Value.absent(),
              updatedAt: Value(timestamp),
              logicalVersion: Value(version),
              deviceId: Value(deviceId),
            ),
          );
          await _enqueue(db, draft.id, 'upsert', version, timestamp);
          updatedTasks++;
        }
        await _saveCheckpoint(db, 'task', draft.externalId, draft.updatedAt);
        continue;
      }
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
              timeMinutes: const Value(null),
              timeZone: const Value(null),
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
      await _enqueue(db, draft.id, 'upsert', 1, timestamp);
      await _saveCheckpoint(db, 'task', draft.externalId, draft.updatedAt);
    }

    if (mode == TodoistImportMode.replace) {
      final oldProjects = await (db.select(
        db.projects,
      )..where((row) => row.externalSource.equals('todoist'))).get();
      for (final project in oldProjects) {
        if (importedProjectIds.contains(project.id) || project.isArchived) {
          continue;
        }
        await (db.update(
          db.projects,
        )..where((row) => row.id.equals(project.id))).write(
          ProjectsCompanion(
            isArchived: const Value(true),
            logicalVersion: Value(project.logicalVersion + 1),
            deviceId: Value(deviceId),
          ),
        );
      }
      final oldSections = await (db.select(
        db.projectSections,
      )..where((row) => row.externalSource.equals('todoist'))).get();
      for (final section in oldSections) {
        if (importedSectionIds.contains(section.id) || section.isArchived) {
          continue;
        }
        await (db.update(
          db.projectSections,
        )..where((row) => row.id.equals(section.id))).write(
          ProjectSectionsCompanion(
            isArchived: const Value(true),
            logicalVersion: Value(section.logicalVersion + 1),
            deviceId: Value(deviceId),
          ),
        );
      }
      final oldTasks = await (db.select(
        db.tasks,
      )..where((row) => row.externalSource.equals('todoist'))).get();
      for (final task in oldTasks) {
        if (importedTaskIds.contains(task.id) || task.deletedAt != null) {
          continue;
        }
        final version = task.logicalVersion + 1;
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals(task.id))).write(
          TasksCompanion(
            deletedAt: Value(timestamp),
            updatedAt: Value(timestamp),
            logicalVersion: Value(version),
            deviceId: Value(deviceId),
          ),
        );
        await _enqueue(db, task.id, 'delete', version, timestamp);
        removedTasks++;
      }
    }

    return TodoistImportResult(
      addedProjects: addedProjects,
      addedSections: addedSections,
      addedTasks: addedTasks,
      updatedTasks: updatedTasks,
      removedTasks: removedTasks,
    );
  });

  Future<String?> _checkpoint(
    AppDatabase db,
    String type,
    String externalId,
  ) async =>
      (await (db.select(db.appSettings)..where(
                (row) => row.key.equals('todoist_updated:$type:$externalId'),
              ))
              .getSingleOrNull())
          ?.value;

  Future<void> _saveCheckpoint(
    AppDatabase db,
    String type,
    String externalId,
    String? value,
  ) async {
    if (value == null) return;
    await _saveSetting(db, 'todoist_updated:$type:$externalId', value);
  }

  Future<void> _saveSetting(AppDatabase db, String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<void> _enqueue(
    AppDatabase db,
    String id,
    String operation,
    int version,
    int timestamp,
  ) => db
      .into(db.outboxEntries)
      .insert(
        OutboxEntriesCompanion.insert(
          operationId: _uuid.v4(),
          entityId: id,
          operation: operation,
          payload: jsonEncode({'id': id, 'version': version}),
          createdAt: timestamp,
        ),
      );

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

  String? _optionalLinkedText(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return linkifyPlainUrls(value.trim());
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
