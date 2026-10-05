import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart' show CivilDate;
import '../../services/agenda_service.dart';
import '../../services/agenda_web_service.dart' show AgendaQueueBusy;
import 'agenda_event_editor.dart';
import 'agenda_event_sheet.dart';

/// `#RRGGBB` or `#AARRGGBB` from the calendar provider.
Color? parseCalendarColor(String? hex) {
  if (hex == null) return null;
  final digits = hex.replaceFirst('#', '');
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return null;
  return switch (digits.length) {
    6 => Color(0xff000000 | value),
    8 => Color(value),
    _ => null,
  };
}

/// Detail, create, edit and delete of Agenda events, shared by every view
/// and by the universal search. Each write is explicit and confirmed where
/// it removes data.
class AgendaEventFlows {
  const AgendaEventFlows({
    required this.service,
    required this.calendars,
    required this.hidden,
    required this.zone,
    this.onOpenTask,
    this.onCreateTask,
  });

  /// Creates a Todo task (title, date, notes) shown in the Agenda; the shell
  /// owns the repository.
  final Future<void> Function(String title, CivilDate date, String notes)?
  onCreateTask;

  final AgendaService service;
  final List<AgendaCalendar> calendars;
  final Set<String> hidden;
  final String? zone;

  /// Opens a Todo task flagged for the Agenda in its editor.
  final Future<void> Function(String taskId)? onOpenTask;

  AgendaCalendar? calendarOf(AgendaEntry entry) =>
      calendars.where((c) => c.id == entry.calendarIds.first).firstOrNull;

  /// Editable here only in a writable calendar and when the user organises
  /// it: changing someone else's invitation would be overwritten by its sync.
  bool editable(AgendaEntry entry) =>
      service.canWrite &&
      (calendarOf(entry)?.writable ?? false) &&
      entry.isOrganizer;

  /// In Todo's own calendar (see [AgendaService.localCalendar]).
  bool localOnly(AgendaEntry entry) => calendarOf(entry)?.localOnly ?? false;

  static const _pendingLocalCalendar = AgendaCalendar(
    id: 'todo-local-pending',
    name: AgendaService.localCalendarName,
    accountName: AgendaService.localAccountName,
    writable: true,
    localOnly: true,
  );

  static const _busyMessage =
      'Il telefono la sta già applicando: riprova tra poco.';

  static void _say(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Detail sheet of an occurrence (or the task editor), then the action.
  /// True when something may have changed (edit, delete, linked task).
  Future<bool> show(BuildContext context, AgendaEntry entry) async {
    if (entry.isTask) {
      await onOpenTask?.call(entry.taskId!);
      return true;
    }
    final calendar = calendarOf(entry);
    final overlaps = await _overlapsOf(entry);
    if (!context.mounted) return false;
    final action = await showAgendaEventSheet(
      context,
      entry: entry,
      calendarName: calendar == null
          ? ''
          : calendar.accountName.isEmpty ||
                calendar.accountName == calendar.name
          ? calendar.name
          : '${calendar.name} · ${calendar.accountName}',
      editable: editable(entry),
      zoneLabel: zone,
      color: parseCalendarColor(calendar?.colorHex),
      canCreateTasks: onCreateTask != null,
      canOpenInCalendar: service.canOpenInSystem,
      localOnly: localOnly(entry),
      canCopyInTodo: service.canCopyInTodo,
      overlaps: overlaps,
    );
    if (!context.mounted || action == null) return false;
    return perform(context, entry, action);
  }

  /// Long press: the frequent actions in a short menu, without the detail
  /// sheet (build 221). True when something may have changed.
  Future<bool> quickActions(BuildContext context, AgendaEntry entry) async {
    if (entry.isTask) return show(context, entry);
    final meeting = entry.meeting;
    final canEdit = editable(entry);
    final local = localOnly(entry);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        Widget item(
          String value,
          IconData icon,
          String label, {
          Color? color,
        }) => ListTile(
          key: ValueKey('agenda-quick-$value'),
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () => Navigator.pop(sheetContext, value),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  entry.title.isEmpty ? '(senza titolo)' : entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (meeting != null)
                item(
                  'join',
                  Icons.videocam_outlined,
                  'Partecipa · ${meeting.provider}',
                ),
              if (onCreateTask != null) ...[
                item('prepare', Icons.playlist_add, 'Preparare (giorno prima)'),
                item(
                  'followUp',
                  Icons.playlist_add_check,
                  'Follow-up (giorno dopo)',
                ),
              ],
              if (canEdit)
                item(
                  'edit',
                  Icons.edit_outlined,
                  local ? 'Modifica' : 'Modifica nel calendario',
                ),
              if (canEdit)
                item(
                  'delete',
                  Icons.delete_outline,
                  local ? 'Elimina' : 'Elimina dal calendario',
                  color: theme.colorScheme.error,
                ),
              if (!local && service.canCopyInTodo)
                item('editInTodo', Icons.edit_note, 'Modifica solo in Todo'),
              if (!local)
                item('hide', Icons.visibility_off_outlined, 'Nascondi in Todo'),
              item('details', Icons.info_outline, 'Dettagli'),
            ],
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return false;
    if (choice == 'join') {
      await launchUrl(meeting!.url, mode: LaunchMode.externalApplication);
      return false;
    }
    if (choice == 'details') return show(context, entry);
    return perform(context, entry, switch (choice) {
      'prepare' => AgendaEventAction.prepareTask,
      'followUp' => AgendaEventAction.followUpTask,
      'edit' => AgendaEventAction.edit,
      'editInTodo' => AgendaEventAction.editInTodo,
      'hide' => AgendaEventAction.hide,
      _ => AgendaEventAction.delete,
    });
  }

  /// Runs one action of the detail sheet or of the quick menu.
  Future<bool> perform(
    BuildContext context,
    AgendaEntry entry,
    AgendaEventAction action,
  ) async {
    switch (action) {
      case AgendaEventAction.edit:
        await edit(context, entry);
      case AgendaEventAction.delete:
        await delete(context, entry);
      case AgendaEventAction.hide:
        await hide(context, entry);
      case AgendaEventAction.editInTodo:
        await editInTodo(context, entry);
      case AgendaEventAction.prepareTask:
      case AgendaEventAction.followUpTask:
        final followUp = action == AgendaEventAction.followUpTask;
        final label = DateFormat(
          entry.allDay ? 'EEE d MMM' : 'EEE d MMM HH:mm',
          'it',
        ).format(entry.start);
        final task = linkedTaskFor(
          entry,
          followUp: followUp,
          eventLabel: '${entry.title} · $label',
        );
        try {
          await onCreateTask!(task.title, task.date, task.notes);
          if (context.mounted) {
            _say(
              context,
              '«${task.title}» per '
              '${DateFormat('EEE d MMM', 'it').format(task.date.asLocalDate)}.',
            );
          }
        } catch (_) {
          if (context.mounted) _say(context, 'Impossibile creare l\'attività.');
        }
      case AgendaEventAction.openInCalendar:
        try {
          await service.openEvent(entry.instanceId);
        } catch (_) {
          if (context.mounted) _say(context, 'Impossibile aprire l\'evento.');
        }
    }
    return action != AgendaEventAction.openInCalendar;
  }

  /// Timed events of the same day that clash with [entry]; empty when the
  /// day cannot be read (the sheet still opens).
  Future<List<AgendaEntry>> _overlapsOf(AgendaEntry entry) async {
    if (entry.allDay || entry.isTask) return const [];
    try {
      final day = (await service.agendaDays(
        CivilDate.fromDateTime(entry.start),
        1,
      )).firstOrNull;
      return agendaOverlaps(day?.entries ?? const [])[entry.instanceId] ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  /// Opens the form and writes the event into the chosen phone calendar.
  Future<void> create(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) async {
    if (!service.canWrite) return;
    final writable = [
      for (final calendar in calendars)
        if (calendar.writable) calendar,
      // Todo's own calendar is offered before it exists and created only
      // when an event is saved into it.
      if (service.canCopyInTodo && !calendars.any((c) => c.localOnly))
        _pendingLocalCalendar,
    ];
    final initialCalendar = defaultEventCalendar(
      calendars,
      await service.lastEventCalendar(),
      hidden: hidden,
    );
    if (!context.mounted) return;
    final now = DateTime.now();
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          calendars: writable,
          initialStart:
              start ?? DateTime(now.year, now.month, now.day, now.hour + 1),
          initialEnd: end,
          initialCalendarId: initialCalendar,
          zoneLabel: zone,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    var target = calendars.where((c) => c.id == draft.calendarId).firstOrNull;
    try {
      if (draft.calendarId == _pendingLocalCalendar.id) {
        target = await service.localCalendar();
        await service.createEvent(draft.inCalendar(target!.id));
      } else {
        await service.createEvent(draft);
      }
      if (!context.mounted) return;
      _say(
        context,
        service.writesViaPhone
            ? 'Inviato al telefono: comparirà in '
                  '${target?.name ?? 'calendario'} appena lo applica.'
            : hidden.contains(draft.calendarId)
            ? 'Evento salvato in ${target?.name ?? 'calendario'}, '
                  'nascosto nell\'Agenda.'
            : 'Evento salvato in ${target?.name ?? 'calendario'}.',
      );
    } catch (_) {
      // Not logged: the draft carries the user's text.
      if (context.mounted) _say(context, 'Impossibile salvare l\'evento.');
    }
  }

  Future<void> edit(BuildContext context, AgendaEntry entry) async {
    final series = entry.recurring
        ? await askSeriesScope(context, delete: false)
        : false;
    if (series == null || !context.mounted) return;
    final AgendaEventDraft? existing;
    try {
      existing = await service.draftFor(entry.instanceId);
    } catch (_) {
      if (context.mounted) _say(context, 'Impossibile leggere l\'evento.');
      return;
    }
    if (!context.mounted) return;
    if (existing == null) {
      _say(context, 'L\'evento non esiste più.');
      return;
    }
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          calendars: [?calendarOf(entry)],
          initialStart: existing!.start,
          existing: existing,
          zoneLabel: zone,
          // Notes are not mirrored to the web: the phone keeps its own.
          notesEditable: !service.writesViaPhone,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    try {
      await service.updateEvent(entry.instanceId, draft, series: series);
      if (context.mounted) {
        _say(
          context,
          service.writesViaPhone
              ? 'Modifica inviata al telefono.'
              : series
              ? 'Serie aggiornata.'
              : 'Evento aggiornato.',
        );
      }
    } on AgendaQueueBusy {
      if (context.mounted) _say(context, _busyMessage);
    } catch (_) {
      // Not logged: the draft carries the user's text.
      if (context.mounted) _say(context, 'Impossibile aggiornare l\'evento.');
    }
  }

  Future<void> delete(BuildContext context, AgendaEntry entry) async {
    final bool? series;
    if (entry.recurring) {
      series = await askSeriesScope(context, delete: true);
    } else {
      series =
          await confirmDelete(context, entry.title, localOnly: localOnly(entry))
          ? false
          : null;
    }
    if (series == null || !context.mounted) return;
    try {
      await service.deleteEvent(entry.instanceId, series: series);
      if (context.mounted) {
        _say(
          context,
          service.writesViaPhone
              ? 'Eliminazione inviata al telefono.'
              : series
              ? 'Serie eliminata.'
              : 'Evento eliminato.',
        );
      }
    } on AgendaQueueBusy {
      if (context.mounted) _say(context, _busyMessage);
    } catch (_) {
      if (context.mounted) _say(context, 'Impossibile eliminare l\'evento.');
    }
  }

  /// Hides [entry] in Todo only: its calendar and account keep it. A
  /// recurring event can be hidden with every event of the same title.
  Future<void> hide(BuildContext context, AgendaEntry entry) async {
    final series = entry.recurring ? await askHideScope(context) : false;
    if (series == null || !context.mounted) return;
    try {
      await service.hideEvent(entry, series: series);
      if (context.mounted) {
        _say(
          context,
          '${series ? 'Serie nascosta' : 'Nascosto'} in Todo; il calendario '
          'non cambia. Si ripristina da Calendari › Nascosti in Todo.',
        );
      }
    } catch (_) {
      if (context.mounted) _say(context, 'Impossibile nascondere l\'evento.');
    }
  }

  /// "Modifica solo in Todo": the occurrence is copied into Todo's own
  /// calendar with the user's changes and the original is hidden here.
  /// Nothing is written to the original calendar or its account.
  Future<void> editInTodo(BuildContext context, AgendaEntry entry) async {
    final AgendaEventDraft? original;
    final AgendaCalendar? target;
    try {
      original = await service.draftFor(entry.instanceId);
      target = original == null ? null : await service.localCalendar();
    } catch (_) {
      if (context.mounted) _say(context, 'Impossibile preparare la copia.');
      return;
    }
    if (!context.mounted) return;
    if (original == null || target == null) {
      _say(context, 'L\'evento non esiste più.');
      return;
    }
    // The meeting link survives in the notes even when the original kept
    // it only in its URL field.
    final link = entry.meeting?.url.toString();
    final notes = original.notes ?? '';
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          heading: 'Modifica solo in Todo',
          calendars: [target!],
          initialStart: original!.start,
          initialCalendarId: target.id,
          prefill: AgendaEventDraft(
            calendarId: target.id,
            title: original.title,
            start: original.start,
            end: original.end,
            allDay: original.allDay,
            location: original.location,
            notes: link == null || notes.contains(link)
                ? notes
                : [notes, link].where((part) => part.isNotEmpty).join('\n\n'),
          ),
          zoneLabel: zone,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    try {
      await service.createEvent(draft);
      await service.hideEvent(entry);
      if (context.mounted) {
        _say(
          context,
          'Copia salvata in Todo; l\'originale resta nel suo calendario, '
          'nascosto qui.',
        );
      }
    } catch (_) {
      // Not logged: the draft carries the user's text.
      if (context.mounted) _say(context, 'Impossibile salvare la copia.');
    }
  }
}
