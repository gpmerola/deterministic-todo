import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/ai_capture.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/ai_capture_actions.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records event writes instead of touching a phone calendar.
class _Agenda extends AgendaService {
  _Agenda(super.database);

  final created = <AgendaEventDraft>[];
  final deleted = <String>[];
  bool failDelete = false;

  @override
  Future<String> createEvent(AgendaEventDraft draft) async {
    created.add(draft);
    return 'event-${created.length}';
  }

  @override
  Future<void> deleteEvent(String instanceId, {bool series = false}) async {
    if (failDelete) throw StateError('provider');
    deleted.add(instanceId);
  }
}

void main() {
  late AppDatabase db;
  late TaskRepository repository;
  late _Agenda agenda;
  late AiCaptureActions actions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(db, deviceId: 'test-device');
    agenda = _Agenda(db);
    actions = AiCaptureActions(repository: repository, agenda: agenda);
  });

  tearDown(() => db.close());

  final start = DateTime(2026, 10, 8, 15);
  final proposals = [
    AiProposal.task(title: 'Preparare slide', date: CivilDate(2026, 10, 8)),
    AiProposal.event(
      title: 'Visita',
      start: start,
      end: start.add(const Duration(hours: 1)),
      calendarId: 'cal',
    ),
  ];

  test('crea attività ed eventi con il marcatore ✨', () async {
    expect(await actions.create(proposals), 2);

    final task = await db.select(db.tasks).getSingle();
    expect(task.title, markAiTitle('Preparare slide'));
    expect(task.showDate, '2026-10-08');
    expect(agenda.created.single.title, markAiTitle('Visita'));
    expect(actions.lastCreated.tasks, [task.id]);
    expect(actions.lastCreated.events, ['event-1']);
  });

  test('annulla: attività nel cestino ed eventi eliminati', () async {
    await actions.create(proposals);

    expect(await actions.undo(actions.lastCreated), 0);
    final task = await db.select(db.tasks).getSingle();
    expect(task.deletedAt, isNotNull);
    expect(agenda.deleted, ['event-1']);
  });

  test('annulla conta gli eventi non eliminati', () async {
    await actions.create(proposals);
    agenda.failDelete = true;

    expect(await actions.undo(actions.lastCreated), 1);
    expect((await db.select(db.tasks).getSingle()).deletedAt, isNotNull);
  });
}
