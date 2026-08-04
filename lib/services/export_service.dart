import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/local/database.dart';

class ImportPreview {
  const ImportPreview({
    required this.added,
    required this.updated,
    required this.unchanged,
  });
  final int added;
  final int updated;
  final int unchanged;
}

class ExportService {
  ExportService(this.db);
  final AppDatabase db;

  Future<String> exportJson() async {
    final tasks = await db.select(db.tasks).get();
    final settings = await db.select(db.appSettings).get();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'deterministic_todo',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'settings': settings.map((setting) => setting.toJson()).toList(),
    });
  }

  Future<String> exportCsv() async {
    final tasks = await db.select(db.tasks).get();
    const columns = [
      'id',
      'title',
      'notes',
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

  Future<ImportPreview> preview(String source) async {
    final root = jsonDecode(source);
    if (root is! Map<String, Object?> ||
        root['format'] != 'deterministic_todo' ||
        root['version'] != 1) {
      throw const FormatException('Formato di backup non supportato');
    }
    final rawTasks = root['tasks'];
    if (rawTasks is! List<Object?>) {
      throw const FormatException('Elenco attività non valido');
    }
    var added = 0;
    var updated = 0;
    var unchanged = 0;
    for (final raw in rawTasks) {
      if (raw is! Map<String, Object?> ||
          raw['id'] is! String ||
          raw['title'] is! String) {
        throw const FormatException('Attività non valida');
      }
      final existing =
          await (db.select(db.tasks)
                ..where((task) => task.id.equals(raw['id']! as String)))
              .getSingleOrNull();
      if (existing == null) {
        added++;
      } else if ((raw['logicalVersion'] as int? ?? 0) >
          existing.logicalVersion) {
        updated++;
      } else {
        unchanged++;
      }
    }
    return ImportPreview(added: added, updated: updated, unchanged: unchanged);
  }

  Future<ImportPreview> importValidated(String source) async {
    final result = await preview(source);
    final root = jsonDecode(source) as Map<String, Object?>;
    final rawTasks = root['tasks']! as List<Object?>;
    await db.transaction(() async {
      for (final raw in rawTasks) {
        final task = Task.fromJson(
          (raw! as Map<String, Object?>).cast<String, dynamic>(),
        );
        final existing = await (db.select(
          db.tasks,
        )..where((row) => row.id.equals(task.id))).getSingleOrNull();
        if (existing != null &&
            existing.logicalVersion >= task.logicalVersion) {
          continue;
        }
        await db.into(db.tasks).insertOnConflictUpdate(task);
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
                }),
                createdAt: DateTime.now().toUtc().microsecondsSinceEpoch,
              ),
            );
      }
    });
    return result;
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';
}
