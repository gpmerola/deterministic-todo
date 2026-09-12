import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/export_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase source, target;
  late ExportService exporter, importer;
  late String project, section;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    source = AppDatabase.forTesting(NativeDatabase.memory());
    target = AppDatabase.forTesting(NativeDatabase.memory());
    exporter = ExportService(source);
    importer = ExportService(target);
    final repo = TaskRepository(source, deviceId: 'synthetic-source');
    project = await repo.createProject('Synthetic project');
    section = await repo.createProjectSection(project, 'Synthetic section');
    await repo.create(
      'Synthetic task',
      projectId: project,
      sectionId: section,
      notes: '[Documento](https://example.com)',
      showDate: '2026-10-02',
    );
    for (final entry in {
      'project_view:$project': 'board',
      'last_quick_project': project,
      'device_id': 'synthetic-source',
      'sync_lamport_counter': '456',
      'calendar_event:synthetic': 'synthetic-mapping',
      'editor_draft:synthetic': 'synthetic-draft',
    }.entries) {
      await source
          .into(source.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: entry.key, value: entry.value),
          );
    }
  });
  tearDown(() async {
    await source.close();
    await target.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'v2 restores hierarchy, content and portable preferences idempotently',
    () async {
      final backup = await exporter.exportJson();
      final root = jsonDecode(backup) as Map;
      expect(root['version'], 2);
      expect(
        (root['settings'] as List)
            .cast<Map<String, dynamic>>()
            .map((r) => r['key'])
            .toSet(),
        {'project_view:$project', 'last_quick_project'},
      );
      await target
          .into(target.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'device_id',
              value: 'synthetic-target',
            ),
          );
      final preview = await importer.preview(backup);
      expect(
        [preview.added, preview.projects, preview.sections, preview.settings],
        [1, 1, 1, 2],
      );
      await importer.importValidated(backup);
      final restored = await target.select(target.tasks).getSingle();
      expect(
        restored.toJson(),
        (await source.select(source.tasks).getSingle()).toJson(),
      );
      expect((await target.select(target.projects).getSingle()).id, project);
      expect(
        (await target.select(target.projectSections).getSingle()).projectId,
        project,
      );
      final settings = {
        for (final r in await target.select(target.appSettings).get())
          r.key: r.value,
      };
      expect(settings['device_id'], 'synthetic-target');
      expect(settings['project_view:$project'], 'board');
      expect(settings.containsKey('calendar_event:synthetic'), false);
      expect(await target.select(target.outboxEntries).get(), hasLength(3));
      await importer.importValidated(backup);
      expect(await target.select(target.outboxEntries).get(), hasLength(3));
    },
  );

  test(
    'legacy backup keeps portable settings but never device or sync state',
    () async {
      final root =
          jsonDecode(await exporter.exportJson()) as Map<String, dynamic>;
      root['version'] = 1;
      root.remove('projects');
      root.remove('sections');
      (root['settings'] as List).add({
        'key': 'device_id',
        'value': 'forbidden-source',
      });
      expect((await importer.preview(jsonEncode(root))).legacy, true);
      await importer.importValidated(jsonEncode(root));
      expect(await target.select(target.tasks).get(), hasLength(1));
      expect(
        await (target.select(
          target.appSettings,
        )..where((r) => r.key.equals('device_id'))).get(),
        isEmpty,
      );
    },
  );

  test('malformed final row and duplicate IDs reject before writing', () async {
    final root =
        jsonDecode(await exporter.exportJson()) as Map<String, dynamic>;
    (root['tasks'] as List).add({'id': 'invalid', 'title': 'Incomplete'});
    await expectLater(
      importer.preview(jsonEncode(root)),
      throwsFormatException,
    );
    await expectLater(
      importer.importValidated(jsonEncode(root)),
      throwsFormatException,
    );
    expect(await target.select(target.projects).get(), isEmpty);
    expect(await target.select(target.outboxEntries).get(), isEmpty);
    final first = (root['tasks'] as List).first;
    root['tasks'] = [first, first];
    await expectLater(
      importer.importValidated(jsonEncode(root)),
      throwsFormatException,
    );
  });

  test('constraint failure rolls back hierarchy and outbox', () async {
    await target.customStatement(
      "CREATE TRIGGER reject_fixture BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    await expectLater(
      importer.importValidated(await exporter.exportJson()),
      throwsA(isA<Exception>()),
    );
    expect(await target.select(target.projects).get(), isEmpty);
    expect(await target.select(target.projectSections).get(), isEmpty);
    expect(await target.select(target.outboxEntries).get(), isEmpty);
  });

  test('newer local rows and purge markers survive restore', () async {
    final backup = await exporter.exportJson();
    await importer.importValidated(backup);
    final task = await target.select(target.tasks).getSingle();
    await (target.update(
      target.tasks,
    )..where((r) => r.id.equals(task.id))).write(
      TasksCompanion(
        title: const Value('Newer synthetic'),
        logicalVersion: Value(task.logicalVersion + 1),
      ),
    );
    await importer.importValidated(backup);
    expect(
      (await target.select(target.tasks).getSingle()).title,
      'Newer synthetic',
    );
    await target
        .into(target.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'purged:tasks:${task.id}',
            value: '1',
          ),
        );
    await target.delete(target.tasks).go();
    expect((await importer.importValidated(backup)).skippedPurged, 1);
    expect(await target.select(target.tasks).get(), isEmpty);
  });
}
