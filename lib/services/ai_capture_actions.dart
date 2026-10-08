import 'package:drift/drift.dart' show OrderingTerm;

import '../data/task_repository.dart';
import '../domain/agenda.dart';
import '../domain/ai_capture.dart';
import 'agenda_service.dart';
import 'agenda_tasks.dart';

/// Items written by one ✨ creation, for its Annulla action.
typedef AiCreatedBatch = ({List<String> tasks, List<String> events});

/// Data side of ✨ Assistente: what the model may see, writing the proposals
/// the user confirmed, and undoing one creation. The shell keeps the pages
/// and messages.
class AiCaptureActions {
  AiCaptureActions({required this.repository, required this.agenda});

  final TaskRepository repository;
  final AgendaService agenda;

  /// What the assistant may use: today, zone, projects, writable calendars
  /// shown in Agenda and their next 14 days of events (filters applied).
  Future<AiCaptureContext> context() async {
    final now = DateTime.now();
    final db = repository.db;
    final projects =
        await (db.select(db.projects)
              ..where((p) => p.isArchived.equals(false))
              ..orderBy([(p) => OrderingTerm(expression: p.position)]))
            .get();
    final zone = await agenda.deviceZoneLabel();
    var calendars = const <({String id, String name})>[];
    String? defaultCalendar;
    var upcoming =
        const <({String title, DateTime start, DateTime end, bool allDay})>[];
    if (await agenda.access() == AgendaAccess.granted) {
      final all = await agenda.calendars();
      final filter = await agenda.filter();
      final hidden = hiddenAgendaCalendars(
        all,
        await agenda.calendarChoices(),
        hideHolidays: filter.hideHolidays,
      );
      calendars = [
        for (final calendar in all)
          if (calendar.writable && !hidden.contains(calendar.id))
            (id: calendar.id, name: calendar.name),
      ];
      // A separate ✨ calendar, if chosen and still writable, wins.
      final aiCalendar = await agenda.aiEventCalendar();
      defaultCalendar = calendars.any((c) => c.id == aiCalendar)
          ? aiCalendar
          : defaultEventCalendar(
              all,
              await agenda.lastEventCalendar(),
              hidden: hidden,
            );
      final today = DateTime(now.year, now.month, now.day);
      final events = await agenda.events(
        today,
        today.add(const Duration(days: 14)),
        [
          for (final calendar in all)
            if (!hidden.contains(calendar.id)) calendar.id,
        ],
      );
      upcoming = [
        for (final entry in mergeAgendaEntries(
          events: events,
          calendars: all,
          hiddenCalendarIds: hidden,
          filter: filter,
        ).take(80))
          (
            title: entry.title,
            start: entry.start,
            end: entry.end,
            allDay: entry.allDay,
          ),
      ];
    }
    return AiCaptureContext(
      now: now,
      zoneLabel: zone,
      projects: [for (final p in projects) (id: p.id, name: p.name)],
      calendars: calendars,
      defaultCalendarId: defaultCalendar,
      upcoming: upcoming,
    );
  }

  /// Items written by the last [create], also when it stopped half way.
  AiCreatedBatch lastCreated = (tasks: const [], events: const []);

  /// Writes confirmed proposals with the ✨ marker; dated tasks are also
  /// shown in the Agenda so the link between list and calendar is visible.
  Future<int> create(List<AiProposal> items) async {
    final db = repository.db;
    final links = AgendaTaskLinks(db);
    final taskIds = <String>[];
    final eventIds = <String>[];
    lastCreated = (tasks: taskIds, events: eventIds);
    var created = 0;
    for (final item in items) {
      if (item.kind == AiProposalKind.task) {
        final id = await repository.create(
          markAiTitle(item.title),
          showDate: item.date?.toString(),
          projectId: item.projectId,
          notes: item.storedNotes(),
        );
        taskIds.add(id);
        if (item.date != null) {
          final task = await (db.select(
            db.tasks,
          )..where((t) => t.id.equals(id))).getSingle();
          await links.setShown(task, true);
        }
      } else {
        final eventId = await agenda.createEvent(
          AgendaEventDraft(
            calendarId: item.calendarId!,
            title: markAiTitle(item.title),
            start: item.start!,
            end: item.end!,
            allDay: item.allDay,
            location: item.location,
            notes: item.storedNotes(),
          ),
        );
        eventIds.add(eventId);
      }
      created++;
    }
    return created;
  }

  /// Removes one ✨ batch: tasks go to the trash (recoverable), events are
  /// deleted from their calendar. Returns the events that could not be
  /// deleted.
  Future<int> undo(AiCreatedBatch batch) async {
    final db = repository.db;
    var failed = 0;
    for (final id in batch.tasks) {
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (task != null && task.deletedAt == null) {
        await repository.softDelete(task);
      }
    }
    for (final id in batch.events) {
      try {
        await agenda.deleteEvent(id);
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }
}
