import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/domain/task_planning.dart';
import 'package:deterministic_todo/services/todoist_import_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// View membership depends on the civil date only; `inbox`, `available` and
/// `scheduled` are interchangeable legacy values. See [legacyOpenStatus].
void main() {
  late AppDatabase db;
  late TaskRepository repo;
  const today = '2026-09-27';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db, deviceId: 'fixture');
  });
  tearDown(() => db.close());

  Future<String> insert(
    String id, {
    required String status,
    String? showDate,
    String? projectId,
  }) async {
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: 'Sintetica $id',
            status: status,
            showDate: Value(showDate),
            projectId: Value(projectId),
            position: 0,
            createdAt: 0,
            updatedAt: 0,
            deviceId: 'fixture',
          ),
        );
    return id;
  }

  Future<Set<String>> view(String name, {String? projectId}) async => {
    for (final task
        in await repo
            .watchView(
              view: name,
              today: today,
              projectId: projectId,
              fromDate: '2026-09-28',
              throughDate: '2026-12-31',
            )
            .first)
      task.id,
  };

  test('le viste ignorano la distinzione legacy tra stati aperti', () async {
    final project = await repo.createProject('Progetto sintetico');
    await insert(
      'future-available',
      status: 'available',
      showDate: '2026-10-01',
    );
    await insert('past-scheduled', status: 'scheduled', showDate: '2026-09-01');
    await insert('today-inbox', status: 'inbox', showDate: today);
    await insert('undated-inbox', status: 'inbox');
    await insert('undated-available', status: 'available');
    await insert('undated-in-project', status: 'available', projectId: project);
    await insert('waiting-today', status: 'waiting', showDate: today);
    await insert('waiting-overdue', status: 'waiting', showDate: '2026-09-01');
    await insert('waiting-future', status: 'waiting', showDate: '2026-10-01');
    await insert('done', status: 'completed', showDate: today);

    expect(await view('today'), {
      'past-scheduled',
      'today-inbox',
      'undated-inbox',
      'undated-available',
      'waiting-today',
    });
    expect(await view('upcoming'), {'future-available'});
    expect(await view('projects', projectId: project), {'undated-in-project'});
    expect(await view('inbox'), isEmpty, reason: 'no separate Inbox view');
  });

  test(
    'lo stato legacy segue la data soltanto quando la data cambia',
    () async {
      final id = await repo.create('Sintetica', showDate: '2999-01-01');
      Future<Task> read() =>
          (db.select(db.tasks)..where((r) => r.id.equals(id))).getSingle();
      expect((await read()).status, TaskStatus.scheduled.name);

      final outboxBefore = (await db.select(db.outboxEntries).get()).length;
      final original = await read();
      await repo.updateDetails(
        original,
        title: 'Rinominata',
        showDate: original.showDate,
      );
      final renamed = await read();
      expect(renamed.status, TaskStatus.scheduled.name);
      final patch =
          jsonDecode((await db.select(db.outboxEntries).get()).last.payload)
              as Map<String, dynamic>;
      expect((patch['changes'] as Map).keys, ['title']);
      expect(
        (await db.select(db.outboxEntries).get()).length,
        outboxBefore + 1,
      );

      await repo.updateDetails(renamed, title: renamed.title, showDate: null);
      expect((await read()).status, TaskStatus.inbox.name);

      await repo.move(await read(), TaskStatus.waiting);
      await repo.updateDetails(
        await read(),
        title: 'In attesa',
        showDate: '2000-01-01',
      );
      expect((await read()).status, TaskStatus.waiting.name);
    },
  );

  test('riaprire una attività futura la riporta in Prossime', () async {
    final id = await repo.create('Futura', showDate: '2999-01-01');
    final task = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(id))).getSingle();
    await repo.setCompleted(task, true);
    final completed = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(id))).getSingle();
    await repo.setCompleted(completed, false);
    final reopened = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(id))).getSingle();
    expect(reopened.status, TaskStatus.scheduled.name);
    expect(legacyOpenStatus(null, CivilDate.parse(today)), TaskStatus.inbox);
  });

  test('Sposta in Inbox è esplicito, sincronizzato e annullabile', () async {
    final project = await repo.createProject('Inbox');
    final section = await repo.createProjectSection(project, 'Sezione');
    final kept = await repo.create('Resta', projectId: project);
    final moved = await repo.create(
      'Spostata',
      projectId: project,
      sectionId: section,
    );
    final other = await repo.createProject('Altro');
    await db.delete(db.outboxEntries).go();

    final row = await (db.select(
      db.projects,
    )..where((r) => r.id.equals(project))).getSingle();
    final placements = await repo.moveProjectToInbox(row);
    expect(placements.map((p) => p.id).toSet(), {kept, moved});
    expect(await view('today'), containsAll([kept, moved]));
    final archived = await (db.select(
      db.projects,
    )..where((r) => r.id.equals(project))).getSingle();
    expect(archived.isArchived, isTrue);
    final outbox = await db.select(db.outboxEntries).get();
    expect(outbox.map((e) => e.entityId), containsAll([kept, moved, project]));

    // A later explicit choice wins over the undo.
    final keptRow = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(kept))).getSingle();
    await repo.updateDetails(
      keptRow,
      title: keptRow.title,
      showDate: keptRow.showDate,
      projectId: other,
      updateProject: true,
    );
    await repo.undoMoveProjectToInbox(archived, placements);
    final tasks = {
      for (final task in await db.select(db.tasks).get()) task.id: task,
    };
    expect(tasks[moved]!.projectId, project);
    expect(tasks[moved]!.sectionId, section);
    expect(tasks[kept]!.projectId, other);
    final restored = await (db.select(
      db.projects,
    )..where((r) => r.id.equals(project))).getSingle();
    expect(restored.isArchived, isFalse);
  });

  test('import Todoist usa il flag inbox_project, non il nome', () async {
    const service = TodoistImportService();
    final plan = service.plan(
      jsonEncode({
        'projects': [
          {'id': 'inbox', 'name': 'Posta', 'inbox_project': true},
          {'id': 'p1', 'name': 'Inbox'},
        ],
        'sections': [
          {'id': 's-inbox', 'project_id': 'inbox', 'name': 'Sezione'},
        ],
        'items': [
          {
            'id': 'i1',
            'content': 'Dalla Inbox',
            'priority': 1,
            'project_id': 'inbox',
            'section_id': 's-inbox',
          },
          {
            'id': 'i2',
            'content': 'Dal progetto',
            'priority': 1,
            'project_id': 'p1',
          },
        ],
      }),
    );
    expect(plan.projects.map((p) => p.name), ['Inbox']);
    expect(plan.sections, isEmpty);
    await service.importPlan(plan: plan, db: db, deviceId: 'fixture');
    final tasks = {
      for (final task in await db.select(db.tasks).get()) task.title: task,
    };
    expect(tasks['Dalla Inbox']!.projectId, isNull);
    expect(tasks['Dalla Inbox']!.sectionId, isNull);
    expect(tasks['Dal progetto']!.projectId, plan.projects.single.id);
  });
}
