import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/services/todoist_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = TodoistImportService();

  test('anteprima conta solo attività Todoist attive', () {
    final preview = service.preview(
      jsonEncode({
        'projects': [
          {'id': 'p1', 'is_deleted': false},
        ],
        'sections': [
          {'id': 's1', 'is_deleted': false},
        ],
        'items': [
          {
            'id': 'i1',
            'checked': false,
            'is_deleted': false,
            'priority': 4,
            'due': {
              'date': '2026-08-04',
              'string': 'ogni giorno',
              'is_recurring': true,
            },
          },
          {'id': 'i2', 'checked': true, 'is_deleted': false, 'priority': 1},
        ],
      }),
    );

    expect(preview.projects, 1);
    expect(preview.sections, 1);
    expect(preview.activeTasks, 1);
    expect(preview.recurringTasks, 1);
    expect(preview.canImport, isTrue);
    expect(preview.priorityCounts, {4: 1});
  });

  test('riconosce la sintassi Todoist ogni 26 come giorno mensile', () {
    final preview = service.preview(
      jsonEncode({
        'projects': <Object>[],
        'sections': <Object>[],
        'items': [
          {
            'id': 'i1',
            'content': 'Pagamento',
            'checked': false,
            'is_deleted': false,
            'priority': 1,
            'due': {
              'date': '2026-08-26',
              'string': 'ogni 26',
              'is_recurring': true,
            },
          },
        ],
      }),
    );

    expect(preview.canImport, isTrue);
    expect(preview.unsupportedRecurrences, isEmpty);
  });

  test('piano preserva progetto, sezione, descrizione e ID deterministici', () {
    final source = jsonEncode({
      'projects': [
        {
          'id': 'p1',
          'name': 'Personale',
          'child_order': 2,
          'is_deleted': false,
        },
      ],
      'sections': [
        {
          'id': 's1',
          'project_id': 'p1',
          'name': 'Casa',
          'section_order': 1,
          'is_deleted': false,
        },
      ],
      'items': [
        {
          'id': 'i1',
          'content': 'Vitamine',
          'description': 'Dopo colazione',
          'project_id': 'p1',
          'section_id': 's1',
          'child_order': 3,
          'checked': false,
          'is_deleted': false,
          'priority': 4,
          'due': {
            'date': '2026-08-05',
            'string': 'ogni giorno',
            'is_recurring': true,
            'timezone': null,
          },
        },
      ],
    });

    final first = service.plan(source);
    final second = service.plan(source);

    expect(first.projects.single.name, 'Personale');
    expect(first.sections.single.projectId, first.projects.single.id);
    expect(first.tasks.single.projectId, first.projects.single.id);
    expect(first.tasks.single.sectionId, first.sections.single.id);
    expect(first.tasks.single.notes, 'Dopo colazione');
    expect(first.tasks.single.showDate, '2026-08-05');
    expect(first.tasks.single.recurrence, 'calendar:day:1');
    expect(second.tasks.single.id, first.tasks.single.id);
  });

  test('import è atomico e ripetibile senza duplicati', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final source = jsonEncode({
      'projects': [
        {
          'id': 'p1',
          'name': 'Personale',
          'child_order': 0,
          'is_deleted': false,
        },
      ],
      'sections': [
        {
          'id': 's1',
          'project_id': 'p1',
          'name': 'Casa',
          'section_order': 0,
          'is_deleted': false,
        },
      ],
      'items': [
        {
          'id': 'i1',
          'content': 'Pagamento',
          'project_id': 'p1',
          'section_id': 's1',
          'child_order': 0,
          'checked': false,
          'is_deleted': false,
          'priority': 4,
          'due': {
            'date': '2026-08-26',
            'string': 'ogni 26',
            'is_recurring': true,
          },
        },
      ],
    });
    final plan = service.plan(source);

    final first = await service.importPlan(
      plan: plan,
      db: db,
      deviceId: '00000000-0000-4000-8000-000000000001',
    );
    final second = await service.importPlan(
      plan: plan,
      db: db,
      deviceId: '00000000-0000-4000-8000-000000000001',
    );

    expect(first.addedProjects, 1);
    expect(first.addedSections, 1);
    expect(first.addedTasks, 1);
    expect(second.addedProjects, 0);
    expect(second.addedSections, 0);
    expect(second.addedTasks, 0);
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(
      (await db.select(db.tasks).getSingle()).recurrence,
      'calendar:month:1',
    );
  });

  test('reimport incrementale aggiorna solo record Todoist cambiati', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    Map<String, Object> export(String title, String updatedAt) => {
      'projects': <Object>[],
      'sections': <Object>[],
      'items': [
        {
          'id': 'i1',
          'content': title,
          'updated_at': updatedAt,
          'child_order': 0,
          'checked': false,
          'is_deleted': false,
          'priority': 1,
        },
      ],
    };

    final first = await service.importPlan(
      plan: service.plan(jsonEncode(export('Prima', '2026-08-04T10:00:00Z'))),
      db: db,
      deviceId: 'device',
    );
    final unchanged = await service.importPlan(
      plan: service.plan(jsonEncode(export('Prima', '2026-08-04T10:00:00Z'))),
      db: db,
      deviceId: 'device',
    );
    final changed = await service.importPlan(
      plan: service.plan(jsonEncode(export('Dopo', '2026-08-04T11:00:00Z'))),
      db: db,
      deviceId: 'device',
    );

    expect(first.addedTasks, 1);
    expect(unchanged.updatedTasks, 0);
    expect(changed.updatedTasks, 1);
    expect((await db.select(db.tasks).getSingle()).title, 'Dopo');
    expect(await db.select(db.outboxEntries).get(), hasLength(2));
  });

  test('sostituzione rimuove solo i record Todoist assenti dal JSON', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const device = 'device';
    final original = jsonEncode({
      'projects': <Object>[],
      'sections': <Object>[],
      'items': [
        {
          'id': 'i1',
          'content': 'Da Todoist',
          'checked': false,
          'is_deleted': false,
          'priority': 1,
        },
      ],
    });
    await service.importPlan(
      plan: service.plan(original),
      db: db,
      deviceId: device,
    );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'locale',
            title: 'Creata nell’app',
            status: 'inbox',
            position: 0,
            createdAt: 1,
            updatedAt: 1,
            deviceId: device,
          ),
        );

    final result = await service.importPlan(
      plan: service.plan(
        jsonEncode({
          'projects': <Object>[],
          'sections': <Object>[],
          'items': <Object>[],
        }),
      ),
      db: db,
      deviceId: device,
      mode: TodoistImportMode.replace,
    );
    final tasks = await db.select(db.tasks).get();

    expect(result.removedTasks, 1);
    expect(tasks.singleWhere((task) => task.id == 'locale').deletedAt, isNull);
    expect(
      tasks.singleWhere((task) => task.externalSource == 'todoist').deletedAt,
      isNotNull,
    );
  });
}
