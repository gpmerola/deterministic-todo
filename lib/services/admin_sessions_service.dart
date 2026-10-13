import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/local/database.dart';
import '../data/task_repository.dart';
import '../domain/admin_sessions.dart';
import '../domain/task.dart';

/// Result of «Rimanda al prossimo slot», with what undo needs.
final class AdminDeferResult {
  const AdminDeferResult({
    required this.outcome,
    this.date,
    this.slot,
    this.before,
  });

  final AdminDeferOutcome outcome;
  final CivilDate? date;
  final AdminSlotOccurrence? slot;

  /// The task as it was; null when nothing changed.
  final Task? before;
}

/// A batch of explicit planning changes, reversible with [AdminSessionsController.undo].
final class AdminChange {
  const AdminChange(this.before);
  final List<Task> before;
  int get count => before.length;
}

/// An open task elsewhere in the app that looks administrative.
final class AdminCopyCandidate {
  const AdminCopyCandidate({
    required this.task,
    required this.section,
    this.projectName,
  });

  final Task task;
  final AdminSection section;
  final String? projectName;
}

/// «Sessioni amministrative» (sperimentale). The slot configuration lives in
/// `app_settings` on this device only; tasks are ordinary rows of the
/// «Amministrazione» project and sync as usual, so no Supabase change is
/// needed. Every write is an explicit user action, recorded in the outbox
/// and the history like any other edit.
class AdminSessionsController extends ChangeNotifier {
  AdminSessionsController(this.repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final TaskRepository repository;
  final DateTime Function() _clock;
  AppDatabase get _db => repository.db;

  AdminSessionsConfig _config = const AdminSessionsConfig();
  AdminSessionsConfig get config => _config;
  bool get enabled => _config.enabled;

  /// Bumped on every saved change: the Calendar reloads its slots.
  int revision = 0;

  CivilDate get today => CivilDate.fromDateTime(_clock());
  int get nowMinutes {
    final now = _clock();
    return now.hour * 60 + now.minute;
  }

  Future<void> load() async {
    final row =
        await (_db.select(_db.appSettings)
              ..where((s) => s.key.equals(AdminSessionsConfig.settingsKey)))
            .getSingleOrNull();
    _config = AdminSessionsConfig.decode(row?.value);
    revision++;
    notifyListeners();
  }

  Future<void> save(AdminSessionsConfig next) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AdminSessionsConfig.settingsKey,
            value: next.encode(),
          ),
        );
    _config = next;
    revision++;
    notifyListeners();
  }

  /// Turning it on creates (once) the project and its five sections; turning
  /// it off hides the section and the actions and leaves every task as is.
  Future<void> setEnabled(bool value) async {
    if (value) await ensureStructure();
    await save(_config.copyWith(enabled: value));
  }

  /// Project and sections with fixed ids: idempotent on every device. A
  /// section the user renamed keeps its name.
  Future<void> ensureStructure() => _db.transaction(() async {
    final projectId = adminProjectId();
    final existing = await (_db.select(
      _db.projects,
    )..where((p) => p.id.equals(projectId))).getSingleOrNull();
    if (existing == null) {
      final rows = await _db.select(_db.projects).get();
      final position =
          rows.fold<int>(
            0,
            (max, row) => row.position > max ? row.position : max,
          ) +
          1024;
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: projectId,
              name: adminProjectName,
              position: position,
              externalSource: const Value(adminExternalSource),
              externalId: const Value('project'),
              deviceId: repository.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else if (existing.isArchived) {
      await repository.updateProject(existing, isArchived: false);
    }
    for (final (index, section) in AdminSection.values.indexed) {
      await _db
          .into(_db.projectSections)
          .insert(
            ProjectSectionsCompanion.insert(
              id: adminSectionId(section),
              projectId: projectId,
              name: section.title,
              position: (index + 1) * 1024,
              externalSource: const Value(adminExternalSource),
              externalId: Value('section:${section.name}'),
              deviceId: repository.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  /// The queue: every not deleted, not completed task of «Amministrazione».
  Stream<List<Task>> watchQueue() => repository.watchView(
    view: 'projects',
    today: today.toString(),
    projectId: adminProjectId(),
  );

  Future<List<Task>> _queue() =>
      (_db.select(_db.tasks)..where(
            (t) =>
                t.projectId.equals(adminProjectId()) &
                t.deletedAt.isNull() &
                t.status.equals(TaskStatus.completed.name).not(),
          ))
          .get();

  static AdminQueueItem item(Task task) =>
      (id: task.id, status: task.status, showDate: task.showDate);

  AdminSlotOccurrence? nextSlot({AdminSlotOccurrence? after}) => nextAdminSlot(
    _config,
    today: today,
    nowMinutes: nowMinutes,
    after: after,
  );

  AdminSlotOccurrence? currentOrLastSlot() =>
      currentOrLastAdminSlot(_config, today: today, nowMinutes: nowMinutes);

  List<AdminSlotOccurrence> slotsBetween(CivilDate first, int days) =>
      adminSlotsBetween(_config, first, days);

  /// The occurrence with this key, looked up around its original date.
  AdminSlotOccurrence? occurrence(String key) {
    final at = key.indexOf('@');
    if (at < 0) return null;
    final CivilDate original;
    try {
      original = CivilDate.parse(key.substring(at + 1));
    } on FormatException {
      return null;
    }
    final override = _config.overrideFor(key);
    final series = _config.seriesById(key.substring(0, at));
    if (series == null) return null;
    if (override?.skipped ?? false) {
      return AdminSlotOccurrence(
        seriesId: series.id,
        label: series.label,
        originalDate: original,
        date: original,
        startMinutes: series.startMinutes,
        durationMinutes: series.durationMinutes,
      );
    }
    final date = override?.date ?? original;
    return slotsBetween(date, 1).where((s) => s.key == key).firstOrNull;
  }

  Future<Task?> _current(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// «Rimanda al prossimo slot»: the task joins the queue (Inbox
  /// amministrativa if it was elsewhere) and takes the next slot's date,
  /// unless its own date comes first. A waiting item becomes open again.
  Future<AdminDeferResult> defer(Task task) async {
    await ensureStructure();
    final current = await _current(task.id) ?? task;
    final next = nextSlot();
    final target = adminDeferTarget(
      showDate: current.showDate,
      today: today,
      next: next,
    );
    if (target.outcome == AdminDeferOutcome.noSlot) {
      return AdminDeferResult(outcome: target.outcome);
    }
    final inQueue = current.projectId == adminProjectId();
    final waitingSection =
        current.sectionId == adminSectionId(AdminSection.waiting);
    await repository.planAdministrative(
      current,
      showDate: Value(target.date.toString()),
      projectId: inQueue ? const Value.absent() : Value(adminProjectId()),
      sectionId: !inQueue || waitingSection
          ? Value(adminSectionId(AdminSection.inbox))
          : const Value.absent(),
      status: current.status == TaskStatus.waiting.name
          ? legacyStatusFor(target.date!)
          : null,
    );
    return AdminDeferResult(
      outcome: target.outcome,
      date: target.date,
      slot: next,
      before: current,
    );
  }

  TaskStatus legacyStatusFor(CivilDate date) =>
      date.compareTo(today) > 0 ? TaskStatus.scheduled : TaskStatus.available;

  /// Puts back date, project, section, status and source as they were.
  Future<void> undo(List<Task> before) => _db.transaction(() async {
    for (final old in before) {
      final current = await _current(old.id);
      if (current == null) continue;
      await repository.planAdministrative(
        current,
        showDate: Value(old.showDate),
        projectId: Value(old.projectId),
        sectionId: Value(old.sectionId),
        status: TaskStatus.values.byName(old.status),
        externalSource: Value(old.externalSource),
        externalId: Value(old.externalId),
      );
    }
  });

  /// «Chiudi sessione»: the residue moves to the following slot, waiting
  /// items keep their check date. The session is remembered as closed.
  Future<({AdminChange change, AdminSlotOccurrence? next})> closeSession(
    AdminSlotOccurrence slot,
  ) async {
    final next = nextSlot(after: slot);
    final moved = <Task>[];
    if (next != null) {
      await _db.transaction(() async {
        final queue = await _queue();
        final residue = adminSessionResidue(queue.map(item), slot).toSet();
        for (final task in queue.where((t) => residue.contains(t.id))) {
          moved.add(task);
          await repository.planAdministrative(
            task,
            showDate: Value(next.date.toString()),
          );
        }
      });
    }
    await save(_config.closing(slot.key, today));
    return (change: AdminChange(moved), next: next);
  }

  /// Open queue tasks dated on the slot's day: they can follow it when it is
  /// moved or skipped.
  Future<int> tasksOn(AdminSlotOccurrence slot) async =>
      adminTasksOnDate((await _queue()).map(item), slot.date).length;

  Future<AdminChange> _moveTasks(CivilDate from, CivilDate to) async {
    final moved = <Task>[];
    if (from == to) return AdminChange(moved);
    await _db.transaction(() async {
      final queue = await _queue();
      final ids = adminTasksOnDate(queue.map(item), from).toSet();
      for (final task in queue.where((t) => ids.contains(t.id))) {
        moved.add(task);
        await repository.planAdministrative(
          task,
          showDate: Value(to.toString()),
        );
      }
    });
    return AdminChange(moved);
  }

  /// Moves one occurrence; with [moveTasks] its tasks follow it.
  Future<AdminChange> moveOccurrence(
    AdminSlotOccurrence slot, {
    required CivilDate date,
    required int startMinutes,
    required int durationMinutes,
    bool moveTasks = true,
  }) async {
    final change = moveTasks
        ? await _moveTasks(slot.date, date)
        : const AdminChange([]);
    await save(
      _config.withOverride(
        AdminSlotOverride(
          seriesId: slot.seriesId,
          originalDate: slot.originalDate,
          date: date,
          startMinutes: startMinutes,
          durationMinutes: durationMinutes,
        ),
      ),
    );
    return change;
  }

  /// Skips one occurrence; with [moveTasks] its tasks go to the next slot.
  Future<({AdminChange change, AdminSlotOccurrence? next})> skipOccurrence(
    AdminSlotOccurrence slot, {
    bool moveTasks = true,
  }) async {
    final skipped = _config.withOverride(
      AdminSlotOverride(
        seriesId: slot.seriesId,
        originalDate: slot.originalDate,
        skipped: true,
      ),
    );
    final next = nextAdminSlot(
      skipped,
      today: today,
      nowMinutes: nowMinutes,
      after: slot,
    );
    final change = moveTasks && next != null
        ? await _moveTasks(slot.date, next.date)
        : const AdminChange([]);
    await save(skipped);
    return (change: change, next: next);
  }

  /// Back to what the series says for this occurrence. Tasks stay where
  /// they are.
  Future<void> restoreOccurrence(AdminSlotOccurrence slot) =>
      save(_config.withoutOverride(slot.key));

  /// New weekday, time or length for a whole series from today on.
  Future<void> updateSeries(AdminSlotSeries series) =>
      save(_config.withSeries(series, today));

  Future<void> setMinutesPerTask(int minutes) =>
      save(_config.copyWith(minutesPerTask: minutes.clamp(1, 240)));

  /// «In attesa»: blocked by someone else, with the date to check again.
  Future<Task?> setWaiting(Task task, CivilDate checkOn) async {
    await ensureStructure();
    final current = await _current(task.id) ?? task;
    await repository.planAdministrative(
      current,
      showDate: Value(checkOn.toString()),
      projectId: Value(adminProjectId()),
      sectionId: Value(adminSectionId(AdminSection.waiting)),
      status: TaskStatus.waiting,
    );
    return current;
  }

  /// Origin and external id; the pair must be unique (future imports
  /// deduplicate on it). Throws [FormatException] on a duplicate.
  Future<void> setSource(
    Task task,
    AdminSource? source,
    String? externalId,
  ) async {
    final current = await _current(task.id) ?? task;
    if (!canSetAdminSource(current.externalSource)) {
      throw const FormatException(
        'Attività importata da Todoist: l’origine non si può cambiare.',
      );
    }
    final id = externalId?.trim();
    final normalizedId = id == null || id.isEmpty ? null : id;
    final storedSource =
        source?.stored ??
        (normalizedId == null ? null : AdminSource.other.stored);
    if (normalizedId != null) {
      final clash =
          await (_db.select(_db.tasks)..where(
                (t) =>
                    t.id.equals(current.id).not() &
                    t.externalSource.equals(storedSource!) &
                    t.externalId.equals(normalizedId),
              ))
              .getSingleOrNull();
      if (clash != null) {
        throw const FormatException(
          'Esiste già un’attività con questa origine e questo ID.',
        );
      }
    }
    await repository.planAdministrative(
      current,
      externalSource: Value(storedSource),
      externalId: Value(normalizedId),
    );
  }

  /// Open tasks outside «Amministrazione» whose title or notes look
  /// administrative, not copied yet. Read only: nothing is written here.
  Future<List<AdminCopyCandidate>> copyCandidates() async {
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.equals(TaskStatus.completed.name).not(),
            ))
            .get();
    final copied = {
      for (final row in rows)
        if (row.externalSource == AdminSource.copy.stored) row.externalId,
    };
    final projects = {
      for (final p in await _db.select(_db.projects).get()) p.id: p,
    };
    final result = <AdminCopyCandidate>[];
    for (final task in rows) {
      if (task.projectId == adminProjectId() || copied.contains(task.id)) {
        continue;
      }
      if (task.projectId != null &&
          (projects[task.projectId]?.isArchived ?? false)) {
        continue;
      }
      final section = suggestAdminSection(task.title, task.notes);
      if (section == null) continue;
      result.add(
        AdminCopyCandidate(
          task: task,
          section: section,
          projectName: projects[task.projectId]?.name,
        ),
      );
    }
    result.sort((a, b) {
      final bySection = a.section.index.compareTo(b.section.index);
      return bySection != 0
          ? bySection
          : a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
    });
    return result;
  }

  /// Copies tasks into the queue; the originals are not touched. Each copy
  /// keeps title, notes and priority, records its original in
  /// `external_source`/`external_id` (so it is never copied twice) and has
  /// no date. Returns the new ids, for undo.
  Future<List<String>> copyToAdmin(
    List<({Task task, AdminSection section})> picks,
  ) async {
    await ensureStructure();
    final created = <String>[];
    await _db.transaction(() async {
      for (final pick in picks) {
        final original = await _current(pick.task.id);
        if (original == null || original.deletedAt != null) continue;
        final duplicate =
            await (_db.select(_db.tasks)..where(
                  (t) =>
                      t.deletedAt.isNull() &
                      t.externalSource.equals(AdminSource.copy.stored) &
                      t.externalId.equals(original.id),
                ))
                .getSingleOrNull();
        if (duplicate != null) continue;
        // Undated: the copy waits in the queue without filling a day next to
        // its original (build 267; build 265 gave copies the slot's date).
        final id = await repository.create(
          original.title,
          notes: original.notes,
          projectId: adminProjectId(),
          sectionId: adminSectionId(pick.section),
          priority: original.priority,
        );
        final copy = await _current(id);
        await repository.planAdministrative(
          copy!,
          externalSource: Value(AdminSource.copy.stored),
          externalId: Value(original.id),
        );
        created.add(id);
      }
    });
    return created;
  }

  /// Undo of [copyToAdmin]: the copies go to the trash.
  Future<void> removeCopies(List<String> ids) => _db.transaction(() async {
    for (final id in ids) {
      final copy = await _current(id);
      if (copy != null && copy.deletedAt == null) {
        await repository.softDelete(copy);
      }
    }
  });

  /// One-off repair of build 265 copies, which took the next slot's date
  /// and doubled their originals in Oggi/Prossime: open copies lose their
  /// date and nothing else. Returns the previous rows, for undo.
  Future<AdminChange> clearCopyDates() async {
    final changed = <Task>[];
    await _db.transaction(() async {
      final copies =
          await (_db.select(_db.tasks)..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.status.equals(TaskStatus.completed.name).not() &
                    t.externalSource.equals(AdminSource.copy.stored) &
                    t.showDate.isNotNull(),
              ))
              .get();
      for (final copy in copies) {
        changed.add(copy);
        await repository.planAdministrative(copy, showDate: const Value(null));
      }
    });
    return AdminChange(changed);
  }
}
