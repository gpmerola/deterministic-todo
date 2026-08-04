import 'dart:convert';

import 'package:deterministic_todo/services/todoist_import_service.dart';
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

  test('anteprima blocca una ricorrenza sconosciuta', () {
    final preview = service.preview(
      jsonEncode({
        'projects': <Object>[],
        'sections': <Object>[],
        'items': [
          {
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

    expect(preview.canImport, isFalse);
    expect(preview.unsupportedRecurrences, ['ogni 26']);
  });
}
