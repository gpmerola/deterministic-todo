import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/recurrence.dart';
import '../domain/task.dart';
import 'local/database.dart';

class TaskRepository {
  TaskRepository(this.db, {required this.deviceId, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final String deviceId;
  final Uuid _uuid;

  Stream<List<Task>> watchAll() =>
      (db.select(db.tasks)
            ..where((task) => task.deletedAt.isNull())
            ..orderBy([
              (task) => OrderingTerm(expression: task.position),
              (task) => OrderingTerm(expression: task.createdAt),
              (task) => OrderingTerm(expression: task.id),
            ]))
          .watch();

  Stream<List<Task>> watchActive() =>
      (db.select(db.tasks)
            ..where(
              (task) =>
                  task.deletedAt.isNull() &
                  task.status.equals(TaskStatus.completed.name).not(),
            )
            ..orderBy([
              (task) => OrderingTerm(expression: task.position),
              (task) => OrderingTerm(expression: task.createdAt),
              (task) => OrderingTerm(expression: task.id),
            ]))
          .watch();

  Stream<List<Task>> watchCompleted({int limit = 200}) =>
      (db.select(db.tasks)
            ..where(
              (task) =>
                  task.deletedAt.isNull() &
                  task.status.equals(TaskStatus.completed.name),
            )
            ..orderBy([
              (task) => OrderingTerm(
                expression: task.completedAt,
                mode: OrderingMode.desc,
              ),
              (task) => OrderingTerm(expression: task.id),
            ])
            ..limit(limit))
          .watch();

  Stream<List<Task>> watchTrash({int limit = 200}) =>
      (db.select(db.tasks)
            ..where((task) => task.deletedAt.isNotNull())
            ..orderBy([
              (task) => OrderingTerm(
                expression: task.deletedAt,
                mode: OrderingMode.desc,
              ),
              (task) => OrderingTerm(expression: task.id),
            ])
            ..limit(limit))
          .watch();

  Future<int> archiveCompletedOlderThan(DateTime cutoff) async {
    final cutoffMicros = cutoff.toUtc().microsecondsSinceEpoch;
    final old =
        await (db.select(db.tasks)..where(
              (task) =>
                  task.deletedAt.isNull() &
                  task.status.equals(TaskStatus.completed.name) &
                  task.completedAt.isNotNull() &
                  task.completedAt.isSmallerThanValue(cutoffMicros),
            ))
            .get();
    for (final task in old) {
      await softDelete(task);
    }
    return old.length;
  }

  Future<void> resetAllLocalData() => db.transaction(() async {
    await db.delete(db.outboxEntries).go();
    await db.delete(db.tasks).go();
    await db.delete(db.projectSections).go();
    await db.delete(db.projects).go();
    await (db.delete(
      db.appSettings,
    )..where((row) => row.key.equals('device_id').not())).go();
  });

  Future<String> create(
    String rawTitle, {
    TaskStatus status = TaskStatus.inbox,
    String? notes,
    String? showDate,
    String? recurrence,
    String? projectId,
    String? sectionId,
    int priority = 1,
  }) async {
    final title = rawTitle.trim();
    if (title.isEmpty) throw const FormatException('Il titolo è obbligatorio');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final maxQuery = db.selectOnly(db.tasks)
      ..addColumns([db.tasks.position.max()]);
    final maxRow = await maxQuery.getSingle();
    final maxPosition = maxRow.read(db.tasks.position.max());
    final row = TasksCompanion.insert(
      id: id,
      title: title,
      status: status.name,
      notes: Value(notes),
      showDate: Value(showDate),
      recurrence: Value(recurrence),
      projectId: Value(projectId),
      sectionId: Value(sectionId),
      priority: Value(priority),
      seriesId: Value(recurrence == null ? null : id),
      occurrenceKey: Value(recurrence == null ? null : showDate),
      position: (maxPosition ?? 0) + 1024,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
    );
    await db.transaction(() async {
      await db.into(db.tasks).insert(row);
      await _enqueue(id, 'upsert', _payloadFromCompanion(row));
    });
    return id;
  }

  Future<String> createProject(String rawName, {String? color}) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const FormatException('Il nome è obbligatorio');
    final id = _uuid.v4();
    final rows = await db.select(db.projects).get();
    final position =
        rows.fold<int>(
          0,
          (max, row) => row.position > max ? row.position : max,
        ) +
        1024;
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            color: Value(color),
            position: position,
            deviceId: deviceId,
          ),
        );
    return id;
  }

  Future<String> createProjectSection(String projectId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const FormatException('Il nome è obbligatorio');
    final id = _uuid.v4();
    final rows = await (db.select(
      db.projectSections,
    )..where((row) => row.projectId.equals(projectId))).get();
    final position =
        rows.fold<int>(
          0,
          (max, row) => row.position > max ? row.position : max,
        ) +
        1024;
    await db
        .into(db.projectSections)
        .insert(
          ProjectSectionsCompanion.insert(
            id: id,
            projectId: projectId,
            name: name,
            position: position,
            deviceId: deviceId,
          ),
        );
    return id;
  }

  Future<void> updateProject(
    Project project, {
    String? name,
    int? position,
    bool? isArchived,
  }) async {
    final normalizedName = name?.trim();
    if (normalizedName != null && normalizedName.isEmpty) {
      throw const FormatException('Il nome è obbligatorio');
    }
    await (db.update(
      db.projects,
    )..where((row) => row.id.equals(project.id))).write(
      ProjectsCompanion(
        name: normalizedName == null
            ? const Value.absent()
            : Value(normalizedName),
        position: position == null ? const Value.absent() : Value(position),
        isArchived: isArchived == null
            ? const Value.absent()
            : Value(isArchived),
        logicalVersion: Value(project.logicalVersion + 1),
        deviceId: Value(deviceId),
      ),
    );
  }

  Future<void> updateProjectSection(
    ProjectSection section, {
    String? name,
    int? position,
    bool? isArchived,
  }) async {
    final normalizedName = name?.trim();
    if (normalizedName != null && normalizedName.isEmpty) {
      throw const FormatException('Il nome è obbligatorio');
    }
    await (db.update(
      db.projectSections,
    )..where((row) => row.id.equals(section.id))).write(
      ProjectSectionsCompanion(
        name: normalizedName == null
            ? const Value.absent()
            : Value(normalizedName),
        position: position == null ? const Value.absent() : Value(position),
        isArchived: isArchived == null
            ? const Value.absent()
            : Value(isArchived),
        logicalVersion: Value(section.logicalVersion + 1),
        deviceId: Value(deviceId),
      ),
    );
  }

  Future<void> swapProjects(Project first, Project second) =>
      db.transaction(() async {
        await updateProject(first, position: second.position);
        await updateProject(second, position: first.position);
      });

  Future<void> swapProjectSections(
    ProjectSection first,
    ProjectSection second,
  ) => db.transaction(() async {
    if (first.projectId != second.projectId) {
      throw const FormatException('Le sezioni appartengono a progetti diversi');
    }
    await updateProjectSection(first, position: second.position);
    await updateProjectSection(second, position: first.position);
  });

  Future<void> setProjectView(String projectId, String view) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'project_view:$projectId',
          value: view,
        ),
      );

  Future<void> setCompleted(Task task, bool completed) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    await _update(
      task,
      TasksCompanion(
        status: Value(
          completed ? TaskStatus.completed.name : TaskStatus.available.name,
        ),
        completedAt: Value(completed ? now : null),
      ),
    );
    final rule = RecurrenceRule.decode(task.recurrence);
    if (completed && rule != null) {
      final today = CivilDate.fromDateTime(DateTime.now());
      if (rule.type == RecurrenceType.afterCompletion) {
        await _insertOccurrence(
          task,
          afterCompletionOccurrence(completedOn: today, rule: rule),
        );
      } else if (task.showDate != null) {
        final anchor = await _seriesAnchor(task);
        var next = nextOccurrence(
          anchor,
          CivilDate.parse(task.showDate!),
          rule,
        );
        while (next.compareTo(today) < 0) {
          next = nextOccurrence(anchor, next, rule);
        }
        await _insertOccurrence(task, next);
      }
    }
  }

  Future<void> undoCompletion(Task task) async {
    final current = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(task.id))).getSingleOrNull();
    if (current == null || current.status != TaskStatus.completed.name) return;
    await db.transaction(() async {
      final completedAt = current.completedAt;
      final seriesId = current.seriesId;
      if (completedAt != null && seriesId != null) {
        final generated =
            await (db.select(db.tasks)
                  ..where(
                    (row) =>
                        row.id.equals(current.id).not() &
                        row.seriesId.equals(seriesId) &
                        row.createdAt.isBiggerOrEqualValue(completedAt),
                  )
                  ..orderBy([
                    (row) => OrderingTerm(
                      expression: row.createdAt,
                      mode: OrderingMode.desc,
                    ),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (generated != null) await softDelete(generated);
      }
      await setCompleted(current, false);
    });
  }

  Future<void> softDelete(Task task) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    await _update(
      task,
      TasksCompanion(deletedAt: Value(now)),
      operation: 'delete',
    );
  }

  Future<void> restore(Task task) async {
    final deleted = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    await _update(
      deleted,
      const TasksCompanion(deletedAt: Value(null)),
      operation: 'upsert',
    );
  }

  Future<void> move(Task task, TaskStatus status) async =>
      _update(task, TasksCompanion(status: Value(status.name)));

  Future<void> updateDetails(
    Task task, {
    required String title,
    String? notes,
    String? showDate,
    String? recurrence,
    String? projectId,
    String? sectionId,
    int? priority,
    bool updateProject = false,
  }) async {
    if (title.trim().isEmpty) {
      throw const FormatException('Il titolo è obbligatorio');
    }
    final seriesId = recurrence != null && task.seriesId == null
        ? _uuid.v4()
        : task.seriesId;
    await _update(
      task,
      TasksCompanion(
        title: Value(title.trim()),
        notes: Value(notes),
        showDate: Value(showDate),
        dueDate: const Value(null),
        timeMinutes: const Value(null),
        timeZone: const Value(null),
        recurrence: Value(recurrence),
        priority: priority == null ? const Value.absent() : Value(priority),
        projectId: updateProject ? Value(projectId) : const Value.absent(),
        sectionId: updateProject ? Value(sectionId) : const Value.absent(),
        seriesId: Value(seriesId),
        occurrenceKey: Value(
          recurrence == null ? null : task.occurrenceKey ?? showDate,
        ),
      ),
    );
  }

  Future<int> generateCalendarOccurrences(Task task, CivilDate through) async {
    final rule = RecurrenceRule.decode(task.recurrence);
    if (rule == null ||
        rule.type != RecurrenceType.calendar ||
        task.showDate == null) {
      return 0;
    }
    var inserted = 0;
    final anchor = CivilDate.parse(task.showDate!);
    for (final date in calendarOccurrences(
      anchor: anchor,
      through: through,
      rule: rule,
    ).skip(1)) {
      inserted += await _insertOccurrence(task, date);
    }
    return inserted;
  }

  Future<int> _insertOccurrence(Task source, CivilDate date) async {
    final seriesId = source.seriesId ?? source.id;
    final id = recurringOccurrenceId(seriesId, date.toString());
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final companion = TasksCompanion.insert(
      id: id,
      title: source.title,
      status: date.compareTo(CivilDate.fromDateTime(DateTime.now())) <= 0
          ? TaskStatus.available.name
          : TaskStatus.scheduled.name,
      showDate: Value(date.toString()),
      dueDate: const Value(null),
      timeMinutes: const Value(null),
      timeZone: const Value(null),
      notes: Value(source.notes),
      priority: Value(source.priority),
      projectId: Value(source.projectId),
      sectionId: Value(source.sectionId),
      position: source.position,
      recurrence: Value(source.recurrence),
      seriesId: Value(seriesId),
      occurrenceKey: Value(date.toString()),
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
    );
    return db.transaction(() async {
      final inserted = await db
          .into(db.tasks)
          .insertReturningOrNull(companion, mode: InsertMode.insertOrIgnore);
      if (inserted != null) {
        await _enqueue(id, 'upsert', _payloadFromCompanion(companion));
      }
      return inserted == null ? 0 : 1;
    });
  }

  Future<CivilDate> _seriesAnchor(Task task) async {
    final seriesId = task.seriesId;
    if (seriesId == null) return CivilDate.parse(task.showDate!);
    final rows =
        await (db.select(db.tasks)
              ..where(
                (row) =>
                    row.seriesId.equals(seriesId) & row.showDate.isNotNull(),
              )
              ..orderBy([(row) => OrderingTerm(expression: row.showDate)])
              ..limit(1))
            .get();
    return CivilDate.parse(
      rows.isEmpty ? task.showDate! : rows.first.showDate!,
    );
  }

  Future<void> reorder(List<Task> ordered) async {
    await db.transaction(() async {
      for (var index = 0; index < ordered.length; index++) {
        final position = (index + 1) * 1024;
        if (ordered[index].position == position) continue;
        await _update(
          ordered[index],
          TasksCompanion(position: Value(position)),
        );
      }
    });
  }

  Future<int> activateScheduled(CivilDate today) async {
    final candidates =
        await (db.select(db.tasks)..where(
              (task) =>
                  task.deletedAt.isNull() &
                  task.status.equals(TaskStatus.scheduled.name) &
                  task.showDate.isNotNull() &
                  task.showDate.isSmallerOrEqualValue(today.toString()),
            ))
            .get();
    for (final task in candidates) {
      await move(task, TaskStatus.available);
    }
    return candidates.length;
  }

  Future<void> _update(
    Task task,
    TasksCompanion changes, {
    String operation = 'upsert',
  }) async {
    final nextVersion = task.logicalVersion + 1;
    final stamped = changes.copyWith(
      updatedAt: Value(DateTime.now().toUtc().microsecondsSinceEpoch),
      logicalVersion: Value(nextVersion),
      deviceId: Value(deviceId),
    );
    await db.transaction(() async {
      await (db.update(
        db.tasks,
      )..where((row) => row.id.equals(task.id))).write(stamped);
      await _enqueue(
        task.id,
        operation,
        jsonEncode({'id': task.id, 'version': nextVersion}),
      );
    });
  }

  Future<void> _enqueue(String id, String operation, String payload) => db
      .into(db.outboxEntries)
      .insert(
        OutboxEntriesCompanion.insert(
          operationId: _uuid.v4(),
          entityId: id,
          operation: operation,
          payload: payload,
          createdAt: DateTime.now().toUtc().microsecondsSinceEpoch,
        ),
      );

  String _payloadFromCompanion(TasksCompanion row) => jsonEncode({
    'id': row.id.value,
    'title': row.title.value,
    'status': row.status.value,
    'logical_version': row.logicalVersion.present
        ? row.logicalVersion.value
        : 1,
    'device_id': row.deviceId.value,
  });
}

String recurringOccurrenceId(String seriesId, String occurrenceKey) =>
    const Uuid().v5(
      Namespace.url.value,
      'deterministic-todo:recurrence:$seriesId:$occurrenceKey',
    );
