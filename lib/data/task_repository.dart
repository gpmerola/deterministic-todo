import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/recurrence.dart';
import '../domain/task.dart';
import '../services/notification_service.dart';
import 'local/database.dart';

class TaskRepository {
  TaskRepository(
    this.db, {
    required this.deviceId,
    this._notifications,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final String deviceId;
  final Uuid _uuid;
  final NotificationService? _notifications;

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

  Stream<List<Task>> watchCompleted() =>
      (db.select(db.tasks)
            ..where(
              (task) =>
                  task.deletedAt.isNull() &
                  task.status.equals(TaskStatus.completed.name),
            )
            ..orderBy([
              (task) => OrderingTerm(expression: task.position),
              (task) => OrderingTerm(expression: task.createdAt),
              (task) => OrderingTerm(expression: task.id),
            ]))
          .watch();

  Future<String> create(
    String rawTitle, {
    TaskStatus status = TaskStatus.inbox,
    String? showDate,
    int? timeMinutes,
    String? timeZone,
    String? recurrence,
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
      showDate: Value(showDate),
      timeMinutes: Value(timeMinutes),
      timeZone: Value(timeZone),
      recurrence: Value(recurrence),
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
    if (showDate != null && timeMinutes != null) {
      final created = await (db.select(
        db.tasks,
      )..where((task) => task.id.equals(id))).getSingle();
      await _notifications?.schedule(created);
    }
    return id;
  }

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
    if (completed) await _notifications?.cancel(task.id);
  }

  Future<void> softDelete(Task task) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    await _update(
      task,
      TasksCompanion(deletedAt: Value(now)),
      operation: 'delete',
    );
    final refreshed = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    await _notifications?.cancel(refreshed.id);
  }

  Future<void> move(Task task, TaskStatus status) async =>
      _update(task, TasksCompanion(status: Value(status.name)));

  Future<void> updateDetails(
    Task task, {
    required String title,
    String? notes,
    String? showDate,
    String? dueDate,
    int? timeMinutes,
    String? timeZone,
    String? recurrence,
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
        dueDate: Value(dueDate),
        timeMinutes: Value(timeMinutes),
        timeZone: Value(timeZone),
        recurrence: Value(recurrence),
        seriesId: Value(seriesId),
        occurrenceKey: Value(
          recurrence == null ? null : task.occurrenceKey ?? showDate,
        ),
      ),
    );
    await _notifications?.cancel(task.id);
    final refreshed = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    if (refreshed.showDate != null && refreshed.timeMinutes != null) {
      await _notifications?.schedule(refreshed);
    }
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
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final companion = TasksCompanion.insert(
      id: id,
      title: source.title,
      status: date.compareTo(CivilDate.fromDateTime(DateTime.now())) <= 0
          ? TaskStatus.available.name
          : TaskStatus.scheduled.name,
      showDate: Value(date.toString()),
      dueDate: Value(source.dueDate == null ? null : date.toString()),
      timeMinutes: Value(source.timeMinutes),
      timeZone: Value(source.timeZone),
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
