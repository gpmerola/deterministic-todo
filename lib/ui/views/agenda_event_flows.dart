import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../services/agenda_service.dart';
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
  });

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
      (calendarOf(entry)?.writable ?? false) && entry.isOrganizer;

  static void _say(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Detail sheet of an occurrence (or the task editor), then the action.
  Future<void> show(BuildContext context, AgendaEntry entry) async {
    if (entry.isTask) {
      await onOpenTask?.call(entry.taskId!);
      return;
    }
    final calendar = calendarOf(entry);
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
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case AgendaEventAction.edit:
        await edit(context, entry);
      case AgendaEventAction.delete:
        await delete(context, entry);
      case AgendaEventAction.openInCalendar:
        try {
          await service.openEvent(entry.instanceId);
        } catch (_) {
          if (context.mounted) _say(context, 'Impossibile aprire l\'evento.');
        }
    }
  }

  /// Opens the form and writes the event into the chosen phone calendar.
  Future<void> create(BuildContext context, {DateTime? start}) async {
    final writable = [
      for (final calendar in calendars)
        if (calendar.writable) calendar,
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
          initialCalendarId: initialCalendar,
          zoneLabel: zone,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    final target = calendars.where((c) => c.id == draft.calendarId).firstOrNull;
    try {
      await service.createEvent(draft);
      if (!context.mounted) return;
      _say(
        context,
        hidden.contains(draft.calendarId)
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
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    try {
      await service.updateEvent(entry.instanceId, draft, series: series);
      if (context.mounted) {
        _say(context, series ? 'Serie aggiornata.' : 'Evento aggiornato.');
      }
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
      series = await confirmDelete(context, entry.title) ? false : null;
    }
    if (series == null || !context.mounted) return;
    try {
      await service.deleteEvent(entry.instanceId, series: series);
      if (context.mounted) {
        _say(context, series ? 'Serie eliminata.' : 'Evento eliminato.');
      }
    } catch (_) {
      if (context.mounted) _say(context, 'Impossibile eliminare l\'evento.');
    }
  }
}
