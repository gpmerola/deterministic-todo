import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/quick_add_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creation preserves sections, links and next-opening project preference',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = TaskRepository(db, deviceId: 'synthetic');
      final project = await repository.createProject('Progetto A');
      final other = await repository.createProject('Progetto B');
      final section = await repository.createProjectSection(
        project,
        'Sezione sintetica',
      );
      final service = QuickAddService(repository);
      await service.refresh();
      await service.create((
        text: 'Leggi domani',
        notes: 'https://example.com',
        priority: 2,
        projectId: project,
        sectionId: section,
      ), projects: service.projects);
      final first = await db.select(db.tasks).getSingle();
      expect(first.sectionId, section);
      expect(first.notes, contains('https://example.com'));
      expect(service.lastProjectId, project);
      await service.create((
        text: 'Rivedi #Progetto B p1 ogni giorno',
        notes: '',
        priority: 1,
        projectId: project,
        sectionId: section,
      ), projects: service.projects);
      final second = (await db.select(db.tasks).get()).singleWhere(
        (t) => t.title == 'Rivedi',
      );
      expect(second.projectId, other);
      expect(second.sectionId, isNull);
      expect(second.priority, 4);
      expect(second.recurrence, isNotNull);
      final fresh = QuickAddService(repository);
      await fresh.refresh();
      expect(fresh.lastProjectId, other);
      expect(fresh.projects, hasLength(2));
    },
  );
}
