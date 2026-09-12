import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';

class ImportPreview {
  const ImportPreview({
    required this.added,
    required this.updated,
    required this.unchanged,
    this.projects = 0,
    this.sections = 0,
    this.settings = 0,
    this.skippedPurged = 0,
    this.legacy = false,
  });
  final int added,
      updated,
      unchanged,
      projects,
      sections,
      settings,
      skippedPurged;
  final bool legacy;
}

/// Portable preferences only. Identity, sync receipts, purge markers, calendar
/// mappings, maintenance timestamps, drafts and health data are never imported.
bool isPortableTodoSetting(String key) =>
    key == 'last_quick_project' || key.startsWith('project_view:');

class _Backup {
  _Backup(this.tasks, this.projects, this.sections, this.settings, this.legacy);
  final List<Task> tasks;
  final List<Project> projects;
  final List<ProjectSection> sections;
  final List<AppSetting> settings;
  final bool legacy;
}

class ExportService {
  ExportService(this.db);
  final AppDatabase db;

  Future<String> exportJson() => db.transaction(() async {
    final tasks = await (db.select(
      db.tasks,
    )..orderBy([(r) => OrderingTerm(expression: r.id)])).get();
    final projects = await (db.select(
      db.projects,
    )..orderBy([(r) => OrderingTerm(expression: r.id)])).get();
    final sections = await (db.select(
      db.projectSections,
    )..orderBy([(r) => OrderingTerm(expression: r.id)])).get();
    final settings = await (db.select(
      db.appSettings,
    )..orderBy([(r) => OrderingTerm(expression: r.key)])).get();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'deterministic_todo',
      'version': 2,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tasks': tasks.map((r) => r.toJson()).toList(),
      'projects': projects.map((r) => r.toJson()).toList(),
      'sections': sections.map((r) => r.toJson()).toList(),
      'settings': settings
          .where((r) => isPortableTodoSetting(r.key))
          .map((r) => r.toJson())
          .toList(),
    });
  });

  Future<String> exportCsv() async {
    final tasks = await db.select(db.tasks).get();
    const columns = [
      'id',
      'title',
      'notes',
      'item_kind',
      'status',
      'show_date',
      'due_date',
      'completed_at',
      'deleted_at',
    ];
    final lines = <String>[columns.join(',')];
    for (final task in tasks) {
      lines.add(
        [
          task.id,
          task.title,
          task.notes ?? '',
          task.itemKind,
          task.status,
          task.showDate ?? '',
          task.dueDate ?? '',
          task.completedAt?.toString() ?? '',
          task.deletedAt?.toString() ?? '',
        ].map(_csvCell).join(','),
      );
    }
    return lines.join('\r\n');
  }

  _Backup _parse(String source) {
    try {
      final root = jsonDecode(source);
      if (root is! Map<String, dynamic> ||
          root['format'] != 'deterministic_todo' ||
          !const [1, 2].contains(root['version'])) {
        throw const FormatException('Formato di backup non supportato');
      }
      final legacy = root['version'] == 1;
      List<T> rows<T>(
        String key,
        T Function(Map<String, dynamic>) decode, {
        bool optional = false,
      }) {
        final raw = root[key];
        if (raw == null && optional) return [];
        if (raw is! List) {
          throw const FormatException('Elenco del backup non valido');
        }
        final ids = <String>{};
        return raw.map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Riga del backup non valida');
          }
          final id = entry[key == 'settings' ? 'key' : 'id'];
          if (id is! String || id.isEmpty || !ids.add(id)) {
            throw const FormatException(
              'Identificatore mancante o duplicato nel backup',
            );
          }
          return decode(entry);
        }).toList();
      }

      final tasks = rows('tasks', (r) {
        final task = Task.fromJson({'itemKind': 'task', ...r});
        if (task.title.trim().isEmpty ||
            task.logicalVersion < 1 ||
            task.priority < 1 ||
            task.priority > 4) {
          throw const FormatException('Attività del backup non valida');
        }
        return task;
      });
      final projects = rows('projects', Project.fromJson, optional: legacy);
      final sections = rows(
        'sections',
        ProjectSection.fromJson,
        optional: legacy,
      );
      if (projects.any((r) => r.name.trim().isEmpty || r.logicalVersion < 1) ||
          sections.any((r) => r.name.trim().isEmpty || r.logicalVersion < 1)) {
        throw const FormatException('Progetto o sezione del backup non validi');
      }
      final settings = rows(
        'settings',
        AppSetting.fromJson,
        optional: legacy,
      ).where((r) => isPortableTodoSetting(r.key)).toList();
      return _Backup(tasks, projects, sections, settings, legacy);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Backup non valido o incompleto');
    }
  }

  Future<bool> _purged(String table, String id) async =>
      await (db.select(
        db.appSettings,
      )..where((r) => r.key.equals('purged:$table:$id'))).getSingleOrNull() !=
      null;

  Future<ImportPreview> preview(String source) =>
      db.transaction(() => _preview(_parse(source)));

  Future<ImportPreview> _preview(_Backup backup) async {
    var added = 0,
        updated = 0,
        unchanged = 0,
        projects = 0,
        sections = 0,
        purged = 0;
    for (final task in backup.tasks) {
      if (await _purged('tasks', task.id)) {
        purged++;
        continue;
      }
      final old = await (db.select(
        db.tasks,
      )..where((r) => r.id.equals(task.id))).getSingleOrNull();
      if (old == null) {
        added++;
      } else if (task.logicalVersion > old.logicalVersion) {
        updated++;
      } else {
        unchanged++;
      }
    }
    for (final row in backup.projects) {
      if (await _purged('projects', row.id)) {
        purged++;
        continue;
      }
      final old = await (db.select(
        db.projects,
      )..where((r) => r.id.equals(row.id))).getSingleOrNull();
      if (old == null || row.logicalVersion > old.logicalVersion) projects++;
    }
    for (final row in backup.sections) {
      if (await _purged('project_sections', row.id)) {
        purged++;
        continue;
      }
      final old = await (db.select(
        db.projectSections,
      )..where((r) => r.id.equals(row.id))).getSingleOrNull();
      if (old == null || row.logicalVersion > old.logicalVersion) sections++;
    }
    return ImportPreview(
      added: added,
      updated: updated,
      unchanged: unchanged,
      projects: projects,
      sections: sections,
      settings: backup.settings.length,
      skippedPurged: purged,
      legacy: backup.legacy,
    );
  }

  Future<ImportPreview> importValidated(String source) async {
    final backup = _parse(source); // Decode every row before any write.
    return db.withRevisionSource('backup_import', () async {
      final result = await _preview(backup);
      // Existing newer rows win. Triggers atomically enqueue project/section intents.
      for (final row in backup.projects) {
        if (await _purged('projects', row.id)) continue;
        final old = await (db.select(
          db.projects,
        )..where((r) => r.id.equals(row.id))).getSingleOrNull();
        if (old == null || row.logicalVersion > old.logicalVersion) {
          await db.into(db.projects).insertOnConflictUpdate(row);
        }
      }
      for (final row in backup.sections) {
        if (await _purged('project_sections', row.id)) continue;
        final old = await (db.select(
          db.projectSections,
        )..where((r) => r.id.equals(row.id))).getSingleOrNull();
        if (old == null || row.logicalVersion > old.logicalVersion) {
          await db.into(db.projectSections).insertOnConflictUpdate(row);
        }
      }
      for (final task in backup.tasks) {
        if (await _purged('tasks', task.id)) continue;
        final old = await (db.select(
          db.tasks,
        )..where((r) => r.id.equals(task.id))).getSingleOrNull();
        if (old != null && old.logicalVersion >= task.logicalVersion) continue;
        await db.into(db.tasks).insertOnConflictUpdate(task.toCompanion(false));
        await db
            .into(db.outboxEntries)
            .insert(
              OutboxEntriesCompanion.insert(
                operationId: const Uuid().v4(),
                entityId: task.id,
                operation: task.deletedAt == null ? 'upsert' : 'delete',
                payload: jsonEncode({
                  'id': task.id,
                  'version': task.logicalVersion,
                  'schema': 2,
                  'kind': 'replace',
                  'snapshot': task.toJson(),
                }),
                createdAt: DateTime.now().toUtc().microsecondsSinceEpoch,
              ),
            );
      }
      for (final setting in backup.settings) {
        if (setting.key.startsWith('project_view:') &&
            !const ['list', 'board'].contains(setting.value)) {
          continue;
        }
        await db.into(db.appSettings).insertOnConflictUpdate(setting);
      }
      return result;
    });
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';
}
