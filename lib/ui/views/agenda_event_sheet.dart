import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';

enum AgendaEventAction {
  edit,
  delete,
  openInCalendar,
  prepareTask,
  followUpTask,
}

/// Google Calendar-like detail of one occurrence. Returns the chosen action.
Future<AgendaEventAction?> showAgendaEventSheet(
  BuildContext context, {
  required AgendaEntry entry,
  required String calendarName,
  required bool editable,
  required String? zoneLabel,
  Color? color,
  bool canCreateTasks = false,
  bool canOpenInCalendar = true,
  List<AgendaEntry> overlaps = const [],
}) => showModalBottomSheet<AgendaEventAction>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => AgendaEventSheet(
    entry: entry,
    calendarName: calendarName,
    editable: editable,
    zoneLabel: zoneLabel,
    color: color,
    canCreateTasks: canCreateTasks,
    canOpenInCalendar: canOpenInCalendar,
    overlaps: overlaps,
  ),
);

class AgendaEventSheet extends StatelessWidget {
  const AgendaEventSheet({
    required this.entry,
    required this.calendarName,
    required this.editable,
    required this.zoneLabel,
    this.color,
    this.canCreateTasks = false,
    this.canOpenInCalendar = true,
    this.overlaps = const [],
    super.key,
  });

  /// Other timed events at the same time (see [agendaOverlaps]).
  final List<AgendaEntry> overlaps;

  /// False on the web: there is no phone calendar app to open.
  final bool canOpenInCalendar;

  /// Shows "Preparare" / "Follow-up": linked Todo tasks before and after.
  final bool canCreateTasks;

  final AgendaEntry entry;
  final String calendarName;
  final bool editable;
  final String? zoneLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = DateFormat('EEEE d MMMM yyyy', 'it');
    final clock = DateFormat.Hm('it');
    final lastDay = entry.end.subtract(const Duration(days: 1));
    final when = entry.allDay
        ? (lastDay.isAfter(entry.start)
              ? '${day.format(entry.start)} – ${day.format(lastDay)}'
              : day.format(entry.start))
        : '${day.format(entry.start)}\n'
              '${clock.format(entry.start)}–${clock.format(entry.end)}';
    final meeting = entry.meeting;
    Widget row(IconData icon, String text, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(child: Text(text, key: key)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 6, right: 16),
                  decoration: BoxDecoration(
                    color: color ?? theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.title.isEmpty ? '(senza titolo)' : entry.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            row(Icons.schedule, when[0].toUpperCase() + when.substring(1)),
            if (!entry.allDay)
              row(
                Icons.public,
                [
                  zoneLabel ?? 'Fuso del telefono non riconosciuto',
                  if (entry.eventZoneTimes != null && entry.timeZone != null)
                    'Orario originale ${entry.eventZoneTimes} ${entry.timeZone}',
                ].join('\n'),
                key: const ValueKey('agenda-sheet-zone'),
              ),
            if (overlaps.isNotEmpty)
              Padding(
                key: const ValueKey('agenda-sheet-overlaps'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        [
                          'Si sovrappone a:',
                          for (final other in overlaps)
                            '${clock.format(other.start)}–'
                                '${clock.format(other.end)} '
                                '${other.title.isEmpty ? '(senza titolo)' : other.title}',
                        ].join('\n'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            if (entry.recurring) row(Icons.repeat, 'Evento ricorrente'),
            if (entry.location?.trim().isNotEmpty ?? false)
              row(Icons.place_outlined, entry.location!.trim()),
            row(Icons.calendar_today_outlined, calendarName),
            if (!editable)
              row(
                Icons.lock_outline,
                entry.isOrganizer
                    ? 'Calendario in sola lettura'
                    : 'Invito di un altro organizzatore: si modifica dal suo '
                          'calendario',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (meeting != null)
                  FilledButton.icon(
                    onPressed: () => unawaited(
                      launchUrl(
                        meeting.url,
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text('Partecipa · ${meeting.provider}'),
                  ),
                if (editable)
                  OutlinedButton.icon(
                    key: const ValueKey('agenda-sheet-edit'),
                    onPressed: () =>
                        Navigator.pop(context, AgendaEventAction.edit),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifica'),
                  ),
                if (editable)
                  OutlinedButton.icon(
                    key: const ValueKey('agenda-sheet-delete'),
                    // Red only for what removes data.
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () =>
                        Navigator.pop(context, AgendaEventAction.delete),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Elimina'),
                  ),
                if (canCreateTasks)
                  OutlinedButton.icon(
                    key: const ValueKey('agenda-sheet-prepare'),
                    onPressed: () =>
                        Navigator.pop(context, AgendaEventAction.prepareTask),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Preparare (giorno prima)'),
                  ),
                if (canCreateTasks)
                  OutlinedButton.icon(
                    key: const ValueKey('agenda-sheet-follow-up'),
                    onPressed: () =>
                        Navigator.pop(context, AgendaEventAction.followUpTask),
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Follow-up (giorno dopo)'),
                  ),
                if (canOpenInCalendar)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      AgendaEventAction.openInCalendar,
                    ),
                    child: const Text('Apri nel calendario'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks whether a change applies to one occurrence or the whole series.
/// Returns null when cancelled.
Future<bool?> askSeriesScope(BuildContext context, {required bool delete}) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          delete ? 'Elimina evento ricorrente' : 'Modifica evento ricorrente',
        ),
        content: const Text(
          'Vale solo per questa occorrenza o per tutta la serie?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          TextButton(
            key: const ValueKey('agenda-scope-series'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tutta la serie'),
          ),
          FilledButton(
            key: const ValueKey('agenda-scope-one'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Solo questa'),
          ),
        ],
      ),
    );

/// Explicit confirmation before deleting from a phone calendar.
Future<bool> confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare l\'evento?'),
        content: Text(
          '«$title» sarà eliminato dal calendario del telefono e dal suo '
          'account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const ValueKey('agenda-confirm-delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    ) ??
    false;
