import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Sessioni amministrative» (builds 264–267) was removed in build 268. Data it
/// left behind on the user's devices must stay exactly as it is: the
/// «Amministrazione» project with its sections and undated copies is now an
/// ordinary project, and the local slot setting is inert.
void main() {
  // Fixed ids written by builds 264–267 (uuid v5 of the old namespace keys).
  const projectId = '4f0b7a3e-0000-5000-8000-000000000001';
  const sectionId = '4f0b7a3e-0000-5000-8000-000000000002';
  const settingsKey = 'admin_sessions_v1';
  const settingsValue =
      '{"enabled":true,"slots":[{"weekday":1,"start":900,"minutes":45}]}';

  Future<Map<String, Object?>> snapshot(AppDatabase db) async => {
    'projects': [
      for (final row in await db.select(db.projects).get()) row.toJson(),
    ],
    'sections': [
      for (final row in await db.select(db.projectSections).get()) row.toJson(),
    ],
    'tasks': [for (final row in await db.select(db.tasks).get()) row.toJson()],
    'outbox': [
      for (final row in await db.select(db.outboxEntries).get()) row.toJson(),
    ],
    'revisions': [
      for (final row in await db.select(db.activityRevisions).get())
        row.toJson(),
    ],
    'adminSetting': (await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(settingsKey))).getSingleOrNull())?.value,
  };

  testWidgets(
    'leftover Admin data is untouched and shown as a normal project',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = TaskRepository(db, deviceId: 'synthetic');

      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: projectId,
              name: 'Amministrazione',
              position: 1024,
              externalSource: const Value('admin'),
              externalId: const Value('project'),
              deviceId: 'synthetic-old-build',
            ),
          );
      await db
          .into(db.projectSections)
          .insert(
            ProjectSectionsCompanion.insert(
              id: sectionId,
              projectId: projectId,
              name: 'Finanza e burocrazia',
              position: 1024,
              externalSource: const Value('admin'),
              externalId: const Value('section:finance'),
              deviceId: 'synthetic-old-build',
            ),
          );
      final copy = await repository.create(
        'Copia sintetica',
        projectId: projectId,
      );
      await (db.update(db.tasks)..where((t) => t.id.equals(copy))).write(
        const TasksCompanion(
          sectionId: Value(sectionId),
          externalSource: Value('admin'),
          externalId: Value('copy:synthetic-original'),
        ),
      );
      await repository.create('Originale sintetico', showDate: '2026-10-14');
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(key: settingsKey, value: settingsValue),
          );
      final before = await snapshot(db);

      await tester.pumpWidget(
        TodoApp(repository: repository, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Admin'), findsNothing);
      await tester.tap(find.text('Prossime'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progetti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amministrazione'));
      await tester.pumpAndSettle();
      expect(find.text('Copia sintetica'), findsOneWidget);
      expect(find.text('Rimanda al prossimo slot'), findsNothing);

      expect(await snapshot(db), before);
      expect(before['adminSetting'], settingsValue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
  );
}
