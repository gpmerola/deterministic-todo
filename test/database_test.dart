import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/notification_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(
      db,
      deviceId: '00000000-0000-4000-8000-000000000001',
    );
  });

  tearDown(() => db.close());

  test('creazione offline salva task e outbox nella stessa base', () async {
    final id = await repository.create('  Pagare bolletta  ');
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    final outbox = await db.select(db.outboxEntries).get();
    expect(task.title, 'Pagare bolletta');
    expect(task.status, TaskStatus.inbox.name);
    expect(outbox.single.entityId, id);
  });

  test('creazione rapida può pianificare data e ora atomicamente', () async {
    final id = await repository.create(
      'Dentista',
      status: TaskStatus.scheduled,
      showDate: '2026-08-05',
      timeMinutes: 570,
      timeZone: 'Europe/London',
    );
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();

    expect(task.status, TaskStatus.scheduled.name);
    expect(task.showDate, '2026-08-05');
    expect(task.timeMinutes, 570);
    expect(task.timeZone, 'Europe/London');
  });

  test('tombstone resta nel database ma sparisce dalla vista attiva', () async {
    final id = await repository.create('Da eliminare');
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    await repository.softDelete(task);
    final persisted = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(persisted.deletedAt, isNotNull);
    expect(await repository.watchAll().first, isEmpty);

    await repository.restore(persisted);
    final restored = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(restored.deletedAt, isNull);
    expect(restored.logicalVersion, persisted.logicalVersion + 1);
    expect(await repository.watchAll().first, hasLength(1));
  });

  test('la generazione calendario ripetuta non duplica occorrenze', () async {
    final id = await repository.create('Controllo mensile');
    var task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    await repository.updateDetails(
      task,
      title: task.title,
      showDate: '2024-01-31',
      recurrence: const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.month,
      ).encode(),
    );
    task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(
      await repository.generateCalendarOccurrences(
        task,
        const CivilDate(2024, 3, 31),
      ),
      2,
    );
    expect(
      await repository.generateCalendarOccurrences(
        task,
        const CivilDate(2024, 3, 31),
      ),
      0,
    );
    final dates =
        (await db.select(db.tasks).get())
            .map((row) => row.showDate)
            .whereType<String>()
            .toList()
          ..sort();
    expect(dates, ['2024-01-31', '2024-02-29', '2024-03-31']);
  });

  test('completare una ricorrenza giornaliera crea il giorno dopo', () async {
    final today = CivilDate.fromDateTime(DateTime.now());
    final id = await repository.create(
      'Vitamine',
      status: TaskStatus.available,
      showDate: today.toString(),
      recurrence: const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      ).encode(),
    );
    final current = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();

    await repository.setCompleted(current, true);

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(2));
    expect(
      tasks
          .singleWhere((task) => task.status != TaskStatus.completed.name)
          .showDate,
      today.addDays(1).toString(),
    );
  });

  test('le viste attive e completate non caricano record inutili', () async {
    final activeId = await repository.create('Attiva');
    final completedId = await repository.create('Completata');
    final completed = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(completedId))).getSingle();
    await repository.setCompleted(completed, true);

    expect((await repository.watchActive().first).single.id, activeId);
    expect((await repository.watchCompleted().first).single.id, completedId);
  });

  test('il riordino invariato non produce scritture o outbox', () async {
    await repository.create('Prima');
    await repository.create('Seconda');
    final ordered = await repository.watchActive().first;
    final before = await db.select(db.outboxEntries).get();

    await repository.reorder(ordered);

    final after = await db.select(db.outboxEntries).get();
    expect(after.length, before.length);
  });

  test('la migrazione crea gli indici delle viste principali', () async {
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'tasks_%_idx' ORDER BY name",
        )
        .get();

    expect(
      indexes.map((row) => row.read<String>('name')),
      containsAll(['tasks_dates_idx', 'tasks_status_order_idx']),
    );
  });

  test('eliminare annulla la notifica senza ripianificarla', () async {
    final notifications = RecordingNotificationService();
    final notifiedRepository = TaskRepository(
      db,
      deviceId: '00000000-0000-4000-8000-000000000001',
      notifications: notifications,
    );
    final id = await notifiedRepository.create(
      'Promemoria',
      status: TaskStatus.scheduled,
      showDate: '2099-08-05',
      timeMinutes: 570,
      timeZone: 'Europe/London',
    );
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();
    notifications.scheduled.clear();
    notifications.cancelled.clear();

    await notifiedRepository.softDelete(task);

    expect(notifications.cancelled, [id]);
    expect(notifications.scheduled, isEmpty);
  });

  test('modificare data e ora ripianifica la notifica', () async {
    final notifications = RecordingNotificationService();
    final notifiedRepository = TaskRepository(
      db,
      deviceId: '00000000-0000-4000-8000-000000000001',
      notifications: notifications,
    );
    final id = await notifiedRepository.create('Promemoria');
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingle();

    await notifiedRepository.updateDetails(
      task,
      title: task.title,
      showDate: '2099-08-05',
      timeMinutes: 600,
      timeZone: 'Europe/London',
    );

    expect(notifications.cancelled, [id]);
    expect(notifications.scheduled.single.id, id);
    expect(notifications.scheduled.single.timeMinutes, 600);
  });

  test('crea progetto, sezione e attività nella destinazione scelta', () async {
    final projectId = await repository.createProject('Ricerca', color: 'blue');
    final sectionId = await repository.createProjectSection(projectId, 'Idee');
    final taskId = await repository.create(
      'Nuovo studio',
      projectId: projectId,
      sectionId: sectionId,
    );

    final project = await db.select(db.projects).getSingle();
    final section = await db.select(db.projectSections).getSingle();
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(taskId))).getSingle();
    expect(project.color, 'blue');
    expect(section.projectId, project.id);
    expect(task.projectId, project.id);
    expect(task.sectionId, section.id);
  });
}

class RecordingNotificationService extends NotificationService {
  final scheduled = <Task>[];
  final cancelled = <String>[];

  @override
  Future<void> schedule(Task task) async => scheduled.add(task);

  @override
  Future<void> cancel(String taskId) async => cancelled.add(taskId);
}
