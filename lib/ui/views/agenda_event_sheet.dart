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

  /// Hidden in Todo only; the calendar keeps it (build 226).
  hide,

  /// Copy edited in Todo's own calendar that replaces the original here.
  editInTodo,

  /// Blocks the event's time in Semble (build 301): offered when the event
  /// is not a visit but falls in bookable Semble time.
  sembleBlock,

  /// Removes, or puts back, the amber edge of this occurrence only (build
  /// 307); Semble and its availability are untouched.
  sembleIgnore,
  sembleUnignore,
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
  bool localOnly = false,
  bool canCopyInTodo = false,
  List<AgendaEntry> overlaps = const [],
  bool canSembleBlock = false,
  bool? sembleIgnored,
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
    localOnly: localOnly,
    canCopyInTodo: canCopyInTodo,
    overlaps: overlaps,
    canSembleBlock: canSembleBlock,
    sembleIgnored: sembleIgnored,
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
    this.localOnly = false,
    this.canCopyInTodo = false,
    this.overlaps = const [],
    this.canSembleBlock = false,
    this.sembleIgnored,
    super.key,
  });

  /// In bookable Semble time: false while the amber edge shows, true once
  /// the user removed it; null otherwise.
  final bool? sembleIgnored;

  /// In Todo's own calendar: Modifica and Elimina change only Todo.
  final bool localOnly;

  /// Offers "Modifica solo in Todo" (phone only).
  final bool canCopyInTodo;

  /// Other timed events at the same time (see [agendaOverlaps]).
  final List<AgendaEntry> overlaps;

  /// The event is in bookable Semble time (amber edge): one button blocks
  /// it there (build 301).
  final bool canSembleBlock;

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
            if (entry.unanswered)
              row(Icons.help_outline, 'Invito ancora senza risposta'),
            if (entry.recurring) row(Icons.repeat, 'Evento ricorrente'),
            if (entry.location?.trim().isNotEmpty ?? false)
              if (agendaMapsUri(entry.location) case final maps?)
                InkWell(
                  key: const ValueKey('agenda-sheet-location'),
                  onTap: () => unawaited(
                    launchUrl(maps, mode: LaunchMode.externalApplication),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            entry.location!.trim(),
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                )
              else
                row(Icons.place_outlined, entry.location!.trim()),
            row(Icons.calendar_today_outlined, calendarName),
            if (localOnly)
              row(
                Icons.phone_android,
                'Solo in Todo: nessun altro calendario lo riceve',
              ),
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
                if (canSembleBlock)
                  FilledButton.icon(
                    key: const ValueKey('agenda-sheet-semble-block'),
                    onPressed: () =>
                        Navigator.pop(context, AgendaEventAction.sembleBlock),
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Blocca in Semble'),
                  ),
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
                    label: Text(
                      localOnly ? 'Modifica' : 'Modifica nel calendario',
                    ),
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
                    label: Text(
                      localOnly ? 'Elimina' : 'Elimina dal calendario',
                    ),
                  ),
                // Rarer actions behind one button (build 299).
                if (!localOnly ||
                    canCreateTasks ||
                    canOpenInCalendar ||
                    sembleIgnored != null)
                  PopupMenuButton<AgendaEventAction>(
                    key: const ValueKey('agenda-sheet-more'),
                    tooltip: 'Altro',
                    onSelected: (action) => Navigator.pop(context, action),
                    itemBuilder: (_) => [
                      if (sembleIgnored == false)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-semble-ignore'),
                          value: AgendaEventAction.sembleIgnore,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.format_color_reset_outlined),
                            title: Text('Togli il bordo ambra'),
                            subtitle: Text('Solo per questo evento'),
                          ),
                        ),
                      if (sembleIgnored == true)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-semble-unignore'),
                          value: AgendaEventAction.sembleUnignore,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.border_left),
                            title: Text('Rimetti il bordo ambra'),
                          ),
                        ),
                      if (!localOnly && canCopyInTodo)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-edit-in-todo'),
                          value: AgendaEventAction.editInTodo,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_note),
                            title: Text('Modifica solo in Todo'),
                          ),
                        ),
                      if (!localOnly)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-hide'),
                          value: AgendaEventAction.hide,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.visibility_off_outlined),
                            title: Text('Nascondi in Todo'),
                          ),
                        ),
                      if (canCreateTasks)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-prepare'),
                          value: AgendaEventAction.prepareTask,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.playlist_add),
                            title: Text('Preparare (giorno prima)'),
                          ),
                        ),
                      if (canCreateTasks)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-follow-up'),
                          value: AgendaEventAction.followUpTask,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.playlist_add_check),
                            title: Text('Follow-up (giorno dopo)'),
                          ),
                        ),
                      if (canOpenInCalendar)
                        const PopupMenuItem(
                          key: ValueKey('agenda-sheet-open'),
                          value: AgendaEventAction.openInCalendar,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.open_in_new),
                            title: Text('Apri nel calendario'),
                          ),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Icon(Icons.more_horiz),
                    ),
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

/// Asks whether "Nascondi" applies to one occurrence or every event with
/// this title. Returns null when cancelled.
Future<bool?> askHideScope(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Nascondi evento ricorrente'),
    content: const Text(
      'Solo in Todo: il calendario non cambia. Nascondere questa occorrenza '
      'o tutti gli eventi con questo titolo?',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Annulla'),
      ),
      TextButton(
        key: const ValueKey('agenda-hide-series'),
        onPressed: () => Navigator.pop(dialogContext, true),
        child: const Text('Tutta la serie'),
      ),
      FilledButton(
        key: const ValueKey('agenda-hide-one'),
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Solo questa'),
      ),
    ],
  ),
);

/// Explicit confirmation before deleting from a phone calendar; with
/// [localOnly] the event is only in Todo's own calendar.
Future<bool> confirmDelete(
  BuildContext context,
  String title, {
  bool localOnly = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare l\'evento?'),
        content: Text(
          localOnly
              ? '«$title» sarà eliminato da Todo.'
              : '«$title» sarà eliminato dal calendario del telefono e dal '
                    'suo account. Per toglierlo solo da Todo usa «Nascondi '
                    'in Todo».',
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
