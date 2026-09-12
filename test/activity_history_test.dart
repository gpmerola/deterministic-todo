import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/ui/activity_history_view.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'revisioni atomiche prima/dopo, rollback e provenienza del pull',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TaskRepository(db, deviceId: 'synthetic-device');
      await repo.create('Prima sintetica', showDate: '2026-09-07');
      final task = await db.select(db.tasks).getSingle();
      await repo.updateDetails(task, title: 'Dopo sintetica', showDate: null);
      var revisions = await db.select(db.activityRevisions).get();
      expect(revisions, hasLength(2));
      expect(
        (jsonDecode(revisions.last.beforeJson!) as Map)['show_date'],
        '2026-09-07',
      );
      expect(
        (jsonDecode(revisions.last.afterJson!) as Map)['show_date'],
        isNull,
      );
      await expectLater(
        db.withRevisionSource('sync_pull', () async {
          await (db.update(db.tasks)..where((r) => r.id.equals(task.id))).write(
            const TasksCompanion(title: Value('Non deve restare')),
          );
          throw StateError('Rollback sintetico');
        }),
        throwsStateError,
      );
      expect(await db.select(db.activityRevisions).get(), hasLength(2));
      await db.withRevisionSource('sync_pull', () async {
        await (db.update(db.tasks)..where((r) => r.id.equals(task.id))).write(
          const TasksCompanion(title: Value('Remota sintetica')),
        );
      });
      revisions = await db.select(db.activityRevisions).get();
      expect(revisions.last.source, 'sync_pull');
      expect(
        await (db.select(
          db.appSettings,
        )..where((r) => r.key.equals('_revision_source'))).get(),
        isEmpty,
      );
      await repo.restoreRevision(task);
      expect(
        (await db.select(db.activityRevisions).get()).last.source,
        'user_restore',
      );
      expect((await db.select(db.tasks).getSingle()).title, task.title);
      await repo.resetAllLocalData();
      expect(await db.select(db.activityRevisions).get(), isEmpty);
    },
  );

  test(
    'lo storico sopravvive alla riapertura e conserva eliminazioni e progetti',
    () async {
      final directory = await Directory.systemTemp.createTemp('todo-history-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/fixture.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final repo = TaskRepository(db, deviceId: 'synthetic-device');
      await repo.createProject('Progetto sintetico');
      await repo.create('Da eliminare');
      await db.delete(db.tasks).go();
      await db.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      final revisions = await reopened.select(reopened.activityRevisions).get();
      expect(revisions, hasLength(3));
      expect(revisions.first.entityType, 'projects');
      expect(revisions.last.operation, 'delete');
      expect(revisions.last.beforeJson, contains('Da eliminare'));
      expect(revisions.last.afterJson, isNull);
    },
  );

  testWidgets('storico filtrato mostra prima/dopo e conferma il ripristino', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepository(db, deviceId: 'synthetic-device');
    final id = await repo.create('Prima sintetica');
    final task = await db.select(db.tasks).getSingle();
    await repo.updateDetails(task, title: 'Dopo sintetica');
    await repo.create('Altra attività esclusa');
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityHistoryView(repository: repo, entityId: id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Altra attività esclusa'), findsNothing);
    await tester.tap(find.text('Dopo sintetica'));
    await tester.pumpAndSettle();
    expect(
      find.text('Prima: Prima sintetica\nDopo: Dopo sintetica'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Usa la versione precedente'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Usa la versione precedente'));
    await tester.pumpAndSettle();
    expect(
      (await (db.select(
        db.tasks,
      )..where((r) => r.id.equals(id))).getSingle()).title,
      'Dopo sintetica',
    );
    await tester.tap(find.text('Usa questa versione').last);
    await tester.pumpAndSettle();
    expect(
      (await (db.select(
        db.tasks,
      )..where((r) => r.id.equals(id))).getSingle()).title,
      'Prima sintetica',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
