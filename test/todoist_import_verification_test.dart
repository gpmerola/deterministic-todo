import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/todoist_import_service.dart';
import 'package:deterministic_todo/services/todoist_import_verification.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic export only: the real personal export is never committed.
String _export({bool withExtra = false}) => jsonEncode({
  'projects': [
    {
      'id': 'inbox',
      'name': 'Inbox',
      'inbox_project': true,
      'is_deleted': false,
    },
    {
      'id': 'p1',
      'name': 'Synthetic project',
      'child_order': 1,
      'is_deleted': false,
    },
  ],
  'sections': [
    {
      'id': 's1',
      'project_id': 'p1',
      'name': 'Synthetic section',
      'section_order': 1,
      'is_deleted': false,
    },
  ],
  'items': [
    {
      'id': 'i1',
      'content': 'Synthetic recurring',
      'description': 'see https://example.com/doc',
      'project_id': 'p1',
      'section_id': 's1',
      'checked': false,
      'is_deleted': false,
      'priority': 4,
      'due': {
        'date': '2026-10-12',
        'string': 'ogni giorno',
        'is_recurring': true,
      },
    },
    {
      'id': 'i2',
      'content': 'Synthetic inbox',
      'project_id': 'inbox',
      'checked': false,
      'is_deleted': false,
      'priority': 1,
    },
    {
      'id': 'i3',
      'content': 'Done',
      'checked': true,
      'is_deleted': false,
      'priority': 2,
    },
    if (withExtra)
      {
        'id': 'i4',
        'content': 'Synthetic dated',
        'checked': false,
        'is_deleted': false,
        'priority': 2,
        'due': {
          'date': '2026-10-20',
          'string': '20 ott',
          'is_recurring': false,
        },
      },
  ],
});

void main() {
  const service = TodoistImportService();
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> replace(String source) => service.importPlan(
    plan: service.plan(source),
    db: db,
    deviceId: 'synthetic-device',
    mode: TodoistImportMode.replace,
  );

  test('after Sostituisci every count and field matches the export', () async {
    await TaskRepository(db, deviceId: 'synthetic-device').create('App only');
    await replace(_export());
    final report = await verifyTodoistImport(db, service.plan(_export()));
    expect(report.ok, isTrue, reason: report.toText());
    expect(report.appOnlyTasks, 1);
    final byLabel = {for (final c in report.checks) c.label: c};
    expect(byLabel['Attività attive']!.actual, 2);
    expect(byLabel['Ricorrenti']!.actual, 1);
    expect(byLabel['Con link']!.actual, 1);
    expect(byLabel['Progetti']!.actual, 1, reason: 'Inbox is not a project');
  });

  test('differences are counted per field and never expose content', () async {
    await replace(_export());
    final id = service.plan(_export()).tasks.first.id;
    await (db.update(db.tasks)..where((r) => r.id.equals(id))).write(
      const TasksCompanion(
        title: Value('Changed private title'),
        priority: Value(1),
        recurrence: Value(null),
      ),
    );
    final report = await verifyTodoistImport(db, service.plan(_export()));
    expect(report.ok, isFalse);
    expect(report.fieldMismatches['Titoli'], 1);
    expect(report.fieldMismatches['Priorità'], 1);
    expect(report.fieldMismatches['Ricorrenze'], 1);
    expect(report.fieldMismatches['Descrizioni'], 0);
    final text = report.toText();
    expect(text, contains('✗ Titoli diversi: 1'));
    for (final secret in ['Changed', 'Synthetic', 'example.com', 'p1', id]) {
      expect(text, isNot(contains(secret)));
    }
  });

  test('a newer export shows the missing task until it is imported', () async {
    await replace(_export());
    final newer = service.plan(_export(withExtra: true));
    var report = await verifyTodoistImport(db, newer);
    final active = report.checks.firstWhere(
      (c) => c.label == 'Attività attive',
    );
    expect((active.expected, active.actual), (3, 2));
    await replace(_export(withExtra: true));
    report = await verifyTodoistImport(db, newer);
    expect(report.ok, isTrue, reason: report.toText());
  });

  test('Todoist rows absent from the export are reported as extra', () async {
    await replace(_export(withExtra: true));
    // Without Sostituisci the old row stays: the report makes it visible.
    final report = await verifyTodoistImport(db, service.plan(_export()));
    expect(
      report.checks
          .firstWhere((c) => c.label == 'Attività Todoist attive in più')
          .actual,
      1,
    );
    await replace(_export());
    expect((await verifyTodoistImport(db, service.plan(_export()))).ok, isTrue);
  });
}
