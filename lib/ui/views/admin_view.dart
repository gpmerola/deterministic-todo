import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local/database.dart';
import '../../domain/admin_sessions.dart';
import '../../domain/task.dart';
import '../../services/admin_sessions_service.dart';
import '../app_undo.dart';
import 'agenda_colors.dart';
import 'task_order.dart';

/// Makes the controller reachable from task rows and sheets. Routes pushed
/// above the shell (search, editors) fall back to [AdminSessionsScope.active].
class AdminSessionsScope extends InheritedNotifier<AdminSessionsController> {
  const AdminSessionsScope({
    required AdminSessionsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The shell's controller, for routes outside its subtree.
  static AdminSessionsController? active;

  static AdminSessionsController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AdminSessionsScope>()
          ?.notifier ??
      active;

  /// Non-null only while the experimental feature is on.
  static AdminSessionsController? enabledOf(BuildContext context) {
    final controller = maybeOf(context);
    return controller != null && controller.enabled ? controller : null;
  }
}

String adminTimeLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String adminDateLabel(CivilDate date) =>
    DateFormat('EEE d MMM', 'it').format(date.asLocalDate);

String adminWeekdayLabel(int weekday) => const [
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
][weekday - 1];

String adminSlotLabel(AdminSlotOccurrence slot) =>
    '${slot.label} · ${adminDateLabel(slot.date)}, '
    '${adminTimeLabel(slot.startMinutes)} · ${slot.durationMinutes} min';

const _durations = [15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 120];

/// «Amministrazione»: only the administrative queue. Deliberately sparse
/// (feedback on build 264): one line for the next slot and the count, the
/// rest in ⋮; only non-empty subsections are shown.
class AdminView extends StatefulWidget {
  const AdminView({
    required this.controller,
    required this.tileBuilder,
    super.key,
  });

  final AdminSessionsController controller;
  final Widget Function(Task task) tileBuilder;

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  late final Stream<List<Task>> queue = widget.controller.watchQueue();

  AdminSessionsController get admin => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: admin,
    builder: (context, _) => StreamBuilder<List<Task>>(
      stream: queue,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? const <Task>[];
        final summary = adminQueueSummary(
          tasks.map(AdminSessionsController.item),
          admin.config,
        );
        final today = admin.today.toString();
        final known = {
          for (final section in AdminSection.values)
            adminSectionId(section): section,
        };
        final bySection = {
          for (final section in AdminSection.values) section: <Task>[],
        };
        for (final task in tasks) {
          bySection[known[task.sectionId] ?? AdminSection.inbox]!.add(task);
        }
        for (final list in bySection.values) {
          list.sort((a, b) => compareByDateThenPriority(a, b, today));
        }
        final theme = Theme.of(context);
        return ListView(
          key: const PageStorageKey('admin-queue'),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
          children: [
            _AdminHeader(controller: admin, summary: summary),
            if (snapshot.hasData && tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text(
                  'Coda vuota. Rimanda un’attività con uno scorrimento verso '
                  'destra, oppure ⋮ → Copia dagli altri progetti.',
                  key: const ValueKey('admin-empty'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final section in AdminSection.values)
              if (bySection[section]!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
                  child: Text(
                    '${section.title} · ${bySection[section]!.length}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final task in bySection[section]!)
                  widget.tileBuilder(task),
              ],
          ],
        );
      },
    ),
  );
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.controller, required this.summary});

  final AdminSessionsController controller;
  final AdminQueueSummary summary;

  @override
  Widget build(BuildContext context) {
    final next = controller.nextSlot();
    final last = controller.currentOrLastSlot();
    final closable = last != null && !controller.config.isClosed(last.key);
    // The button appears only on the session's own day; later it stays in ⋮.
    final closeNow = closable && last.date == controller.today;
    final counts = [
      '${summary.open} in coda',
      if (summary.waiting > 0) '${summary.waiting} in attesa',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('admin-next-slot'),
          contentPadding: const EdgeInsets.only(left: 12),
          leading: const Icon(Icons.event_note, color: adminSlotColor),
          title: Text(
            next == null
                ? 'Nessuno slot in programma'
                : 'Prossimo: ${next.label}, ${adminDateLabel(next.date)} '
                      '${adminTimeLabel(next.startMinutes)}',
          ),
          subtitle: Text(counts, key: const ValueKey('admin-queue-summary')),
          onTap: next == null
              ? null
              : () => showAdminSlotSheet(context, controller, next.key),
          trailing: PopupMenuButton<String>(
            key: const ValueKey('admin-menu'),
            tooltip: 'Altre azioni',
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  showAdminCopySheet(context, controller);
                case 'slots':
                  showAdminSlotsSheet(context, controller);
                case 'undate':
                  clearAdminCopyDates(context, controller);
                case 'close':
                  closeAdminSession(context, controller, last!);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: ValueKey('admin-menu-copy'),
                value: 'copy',
                child: Text('Copia dagli altri progetti'),
              ),
              const PopupMenuItem(
                key: ValueKey('admin-menu-undate'),
                value: 'undate',
                child: Text('Togli la data alle copie'),
              ),
              const PopupMenuItem(
                key: ValueKey('admin-edit-slots'),
                value: 'slots',
                child: Text('Modifica slot'),
              ),
              if (closable)
                PopupMenuItem(
                  value: 'close',
                  child: Text(
                    'Chiudi ${last.label} di ${adminDateLabel(last.date)}',
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  summary.open == 0
                      ? 'Stima: nessuna attività'
                      : 'Stima: circa ${summary.estimatedMinutes} min',
                ),
              ),
            ],
          ),
        ),
        if (closeNow)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: FilledButton.tonalIcon(
              key: const ValueKey('admin-close-session'),
              onPressed: () => closeAdminSession(context, controller, last),
              icon: const Icon(Icons.done_all),
              label: Text('Chiudi ${last.label}'),
            ),
          ),
      ],
    );
  }
}

/// Proposals of administrative-looking tasks from the other projects, each
/// with a checkbox and its target subsection. Copies only what is ticked;
/// the originals stay where they are.
Future<void> showAdminCopySheet(
  BuildContext context,
  AdminSessionsController controller,
) async {
  final candidates = await controller.copyCandidates();
  if (!context.mounted) return;
  if (candidates.isEmpty) {
    _say(context, 'Nessuna attività burocratica riconosciuta da copiare');
    return;
  }
  final picks =
      await showModalBottomSheet<List<({Task task, AdminSection section})>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _AdminCopySheet(candidates: candidates),
      );
  if (picks == null || picks.isEmpty || !context.mounted) return;
  final created = await controller.copyToAdmin(picks);
  if (!context.mounted) return;
  AppUndo.show(
    context,
    message: created.length == 1
        ? '1 attività copiata in Admin; l’originale resta dov’era'
        : '${created.length} attività copiate in Admin; gli originali restano',
    undo: () => controller.removeCopies(created),
    duration: const Duration(seconds: 8),
  );
}

class _AdminCopySheet extends StatefulWidget {
  const _AdminCopySheet({required this.candidates});
  final List<AdminCopyCandidate> candidates;

  @override
  State<_AdminCopySheet> createState() => _AdminCopySheetState();
}

class _AdminCopySheetState extends State<_AdminCopySheet> {
  late final selected = {for (final c in widget.candidates) c.task.id};
  late final sections = {
    for (final c in widget.candidates) c.task.id: c.section,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          title: const Text('Copia in Admin'),
          subtitle: const Text(
            'Proposte riconosciute dalle parole del titolo. Gli originali '
            'non cambiano. Tocca la sottosezione per cambiarla.',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              for (final c in widget.candidates)
                CheckboxListTile(
                  key: ValueKey('admin-copy-${c.task.id}'),
                  value: selected.contains(c.task.id),
                  onChanged: (value) => setState(
                    () => value == true
                        ? selected.add(c.task.id)
                        : selected.remove(c.task.id),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(c.task.title, maxLines: 2),
                  subtitle: Text(
                    [
                      c.projectName ?? 'Inbox',
                      if (c.task.showDate != null)
                        adminDateLabel(CivilDate.parse(c.task.showDate!)),
                    ].join(' · '),
                  ),
                  secondary: PopupMenuButton<AdminSection>(
                    tooltip: 'Sottosezione',
                    initialValue: sections[c.task.id],
                    onSelected: (value) =>
                        setState(() => sections[c.task.id] = value),
                    itemBuilder: (_) => [
                      for (final section in AdminSection.values)
                        if (section != AdminSection.waiting)
                          PopupMenuItem(
                            value: section,
                            child: Text(section.title),
                          ),
                    ],
                    child: Text(
                      sections[c.task.id]!.title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annulla'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('admin-copy-confirm'),
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                          for (final c in widget.candidates)
                            if (selected.contains(c.task.id))
                              (task: c.task, section: sections[c.task.id]!),
                        ]),
                  child: Text('Copia ${selected.length}'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Copies made by build 265 carry the slot's date; this removes it.
Future<void> clearAdminCopyDates(
  BuildContext context,
  AdminSessionsController controller,
) async {
  final change = await controller.clearCopyDates();
  if (!context.mounted) return;
  if (change.count == 0) {
    _say(context, 'Nessuna copia con data');
    return;
  }
  AppUndo.show(
    context,
    message: change.count == 1
        ? 'Tolta la data a 1 copia; gli originali non cambiano'
        : 'Tolta la data a ${change.count} copie; gli originali non cambiano',
    undo: () => controller.undo(change.before),
    duration: const Duration(seconds: 8),
  );
}

void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
}

Future<void> closeAdminSession(
  BuildContext context,
  AdminSessionsController controller,
  AdminSlotOccurrence slot,
) async {
  final next = controller.nextSlot(after: slot);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Chiudere ${slot.label}?'),
      content: Text(
        next == null
            ? 'Nessuno slot successivo nelle prossime 10 settimane: le '
                  'attività restano dove sono.'
            : 'Le attività aperte di questa sessione passano a '
                  '${adminSlotLabel(next)}. Quelle in attesa conservano la '
                  'data di controllo, quelle con una data successiva la loro.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const ValueKey('admin-close-confirm'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Chiudi sessione'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final result = await controller.closeSession(slot);
  if (!context.mounted) return;
  final moved = result.change.count;
  AppUndo.show(
    context,
    message: moved == 0
        ? 'Sessione chiusa: nessun residuo'
        : 'Sessione chiusa: $moved ${moved == 1 ? 'attività passa' : 'attività passano'} '
              'a ${result.next!.label} di ${adminDateLabel(result.next!.date)}',
    undo: () => controller.undo(result.change.before),
  );
}

/// Series and the next occurrences, each editable.
Future<void> showAdminSlotsSheet(
  BuildContext context,
  AdminSessionsController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => ListenableBuilder(
    listenable: controller,
    builder: (sheetContext, _) {
      final config = controller.config;
      final upcoming = controller.slotsBetween(controller.today, 28);
      final skipped = [
        for (final o in config.overrides)
          if (o.skipped && o.originalDate.compareTo(controller.today) >= 0) o,
      ]..sort((a, b) => a.originalDate.compareTo(b.originalDate));
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ListTile(
            title: Text('Slot settimanali'),
            subtitle: Text(
              'Valgono su questo dispositivo. Tocca per cambiare giorno, ora '
              'o durata di tutte le settimane.',
            ),
          ),
          for (final series in config.series)
            ListTile(
              key: ValueKey('admin-series-${series.id}'),
              leading: const Icon(Icons.repeat),
              title: Text(series.label),
              subtitle: Text(
                'Ogni ${adminWeekdayLabel(series.weekday)}, '
                '${adminTimeLabel(series.startMinutes)} · '
                '${series.durationMinutes} min',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => editAdminSeries(sheetContext, controller, series),
            ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Stima per attività'),
            subtitle: Text(
              '${config.minutesPerTask} min: serve solo a mostrare la coda',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final value = await _pickDuration(
                sheetContext,
                'Stima per attività',
                config.minutesPerTask,
                const [5, 10, 15, 20, 30],
              );
              if (value != null) await controller.setMinutesPerTask(value);
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('Prossime 4 settimane'),
            subtitle: Text('Tocca uno slot per spostarlo o saltarlo'),
          ),
          for (final slot in upcoming)
            ListTile(
              key: ValueKey('admin-occurrence-${slot.key}'),
              leading: Icon(
                slot.moved ? Icons.edit_calendar : Icons.event_outlined,
                color: adminSlotColor,
              ),
              title: Text(adminSlotLabel(slot)),
              subtitle: slot.moved ? const Text('Spostato') : null,
              onTap: () =>
                  showAdminSlotSheet(sheetContext, controller, slot.key),
            ),
          for (final o in skipped)
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(
                '${config.seriesById(o.seriesId)?.label ?? o.seriesId} · '
                '${adminDateLabel(o.originalDate)}',
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              subtitle: const Text('Saltato'),
              trailing: TextButton(
                onPressed: () => controller.save(config.withoutOverride(o.key)),
                child: const Text('Ripristina'),
              ),
            ),
        ],
      );
    },
  ),
);

/// One occurrence: move, skip, restore, or change its whole series. Opened
/// from the Calendar block and from «Amministrazione». True when changed.
Future<bool> showAdminSlotSheet(
  BuildContext context,
  AdminSessionsController controller,
  String key,
) async {
  final slot = controller.occurrence(key);
  if (slot == null) return false;
  final override = controller.config.overrideFor(key);
  final skipped = override?.skipped ?? false;
  final started = !slot.startsAfter(controller.today, controller.nowMinutes);
  final closable = started && !skipped && !controller.config.isClosed(key);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.event_note, color: adminSlotColor),
            title: Text(slot.label),
            subtitle: Text(
              skipped
                  ? 'Saltato: ${adminDateLabel(slot.originalDate)}'
                  : '${adminDateLabel(slot.date)}, '
                        '${adminTimeLabel(slot.startMinutes)}–'
                        '${adminTimeLabel(slot.startMinutes + slot.durationMinutes)}'
                        '${slot.moved ? ' · spostato' : ''}',
            ),
          ),
          const Divider(height: 1),
          if (!skipped)
            ListTile(
              key: const ValueKey('admin-slot-move'),
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Sposta solo questa volta'),
              onTap: () => Navigator.pop(sheetContext, 'move'),
            ),
          if (!skipped)
            ListTile(
              key: const ValueKey('admin-slot-skip'),
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Salta questa volta'),
              onTap: () => Navigator.pop(sheetContext, 'skip'),
            ),
          if (override != null)
            ListTile(
              key: const ValueKey('admin-slot-restore'),
              leading: const Icon(Icons.restore),
              title: const Text('Ripristina come da serie'),
              onTap: () => Navigator.pop(sheetContext, 'restore'),
            ),
          ListTile(
            key: const ValueKey('admin-slot-series'),
            leading: const Icon(Icons.repeat),
            title: const Text('Cambia tutte le settimane'),
            onTap: () => Navigator.pop(sheetContext, 'series'),
          ),
          if (closable)
            ListTile(
              key: const ValueKey('admin-slot-close'),
              leading: const Icon(Icons.done_all),
              title: const Text('Chiudi sessione'),
              subtitle: const Text('Il residuo passa allo slot successivo'),
              onTap: () => Navigator.pop(sheetContext, 'close'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  switch (choice) {
    case 'move':
      return _moveOccurrence(context, controller, slot);
    case 'skip':
      return _skipOccurrence(context, controller, slot);
    case 'restore':
      await controller.restoreOccurrence(slot);
      if (context.mounted) {
        _say(context, '${slot.label} ripristinato come da serie');
      }
      return true;
    case 'series':
      final series = controller.config.seriesById(slot.seriesId);
      if (series == null) return false;
      return editAdminSeries(context, controller, series);
    case 'close':
      await closeAdminSession(context, controller, slot);
      return true;
  }
  return false;
}

Future<bool?> _askMoveTasks(BuildContext context, int count, String where) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          count == 1
              ? '1 attività è prevista per questo slot'
              : '$count attività sono previste per questo slot',
        ),
        content: Text('Spostarle $where?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Lasciale'),
          ),
          FilledButton(
            key: const ValueKey('admin-move-tasks-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Spostale'),
          ),
        ],
      ),
    );

Future<bool> _moveOccurrence(
  BuildContext context,
  AdminSessionsController controller,
  AdminSlotOccurrence slot,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: slot.date.asLocalDate,
    firstDate: controller.today.asLocalDate,
    lastDate: controller.today.addDays(366).asLocalDate,
    helpText: 'Nuovo giorno per ${slot.label}',
  );
  if (date == null || !context.mounted) return false;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: slot.startMinutes ~/ 60,
      minute: slot.startMinutes % 60,
    ),
    helpText: 'Ora di inizio',
  );
  if (time == null || !context.mounted) return false;
  final duration = await _pickDuration(
    context,
    'Durata',
    slot.durationMinutes,
    _durations,
  );
  if (duration == null || !context.mounted) return false;
  final target = CivilDate.fromDateTime(date);
  final count = target == slot.date ? 0 : await controller.tasksOn(slot);
  var moveTasks = false;
  if (count > 0 && context.mounted) {
    final answer = await _askMoveTasks(
      context,
      count,
      'a ${adminDateLabel(target)}',
    );
    if (answer == null) return false;
    moveTasks = answer;
  }
  final change = await controller.moveOccurrence(
    slot,
    date: target,
    startMinutes: time.hour * 60 + time.minute,
    durationMinutes: duration,
    moveTasks: moveTasks,
  );
  if (context.mounted) {
    _say(
      context,
      '${slot.label} spostato a ${adminDateLabel(target)}, '
      '${adminTimeLabel(time.hour * 60 + time.minute)}'
      '${change.count == 0 ? '' : ' con ${change.count} attività'}',
    );
  }
  return true;
}

Future<bool> _skipOccurrence(
  BuildContext context,
  AdminSessionsController controller,
  AdminSlotOccurrence slot,
) async {
  final count = await controller.tasksOn(slot);
  var moveTasks = false;
  if (count > 0 && context.mounted) {
    final answer = await _askMoveTasks(context, count, 'al prossimo slot');
    if (answer == null) return false;
    moveTasks = answer;
  }
  final result = await controller.skipOccurrence(slot, moveTasks: moveTasks);
  if (context.mounted) {
    _say(
      context,
      '${slot.label} di ${adminDateLabel(slot.date)} saltato'
      '${result.change.count == 0 || result.next == null ? '' : ': ${result.change.count} attività a ${adminDateLabel(result.next!.date)}'}',
    );
  }
  return true;
}

Future<int?> _pickDuration(
  BuildContext context,
  String title,
  int current,
  List<int> options,
) => showDialog<int>(
  context: context,
  builder: (dialogContext) => SimpleDialog(
    title: Text(title),
    children: [
      for (final minutes in {...options, current}.toList()..sort())
        SimpleDialogOption(
          key: ValueKey('admin-duration-$minutes'),
          onPressed: () => Navigator.pop(dialogContext, minutes),
          child: Text(
            '$minutes min',
            style: minutes == current
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
        ),
    ],
  ),
);

/// Weekday, time and length of a whole series, from today on. Its future
/// single moves and skips are reset (they referred to the old timing).
Future<bool> editAdminSeries(
  BuildContext context,
  AdminSessionsController controller,
  AdminSlotSeries series,
) async {
  var weekday = series.weekday;
  var start = series.startMinutes;
  var duration = series.durationMinutes;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(series.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<int>(
              key: const ValueKey('admin-series-weekday'),
              value: weekday,
              isExpanded: true,
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text('Ogni ${adminWeekdayLabel(day)}'),
                  ),
              ],
              onChanged: (value) =>
                  setDialogState(() => weekday = value ?? weekday),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('Inizio ${adminTimeLabel(start)}'),
              onTap: () async {
                final time = await showTimePicker(
                  context: dialogContext,
                  initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
                );
                if (time != null) {
                  setDialogState(() => start = time.hour * 60 + time.minute);
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text('Durata $duration min'),
              onTap: () async {
                final value = await _pickDuration(
                  dialogContext,
                  'Durata',
                  duration,
                  _durations,
                );
                if (value != null) setDialogState(() => duration = value);
              },
            ),
            if (controller.config.overrides.any((o) => o.seriesId == series.id))
              const Text(
                'Le singole occorrenze future spostate o saltate tornano come '
                'da serie.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const ValueKey('admin-series-save'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return false;
  await controller.updateSeries(
    series.copyWith(
      weekday: weekday,
      startMinutes: start,
      durationMinutes: duration,
    ),
  );
  return true;
}

/// «Rimanda al prossimo slot» with its feedback and undo.
Future<void> deferToAdminSlot(
  BuildContext context,
  AdminSessionsController controller,
  Task task,
) async {
  final result = await controller.defer(task);
  if (!context.mounted) return;
  switch (result.outcome) {
    case AdminDeferOutcome.noSlot:
      _say(context, 'Nessuno slot amministrativo nelle prossime 10 settimane');
    case AdminDeferOutcome.slot:
      AppUndo.show(
        context,
        message: 'Rimandata a ${adminSlotLabel(result.slot!)}',
        undo: () => controller.undo([result.before!]),
      );
    case AdminDeferOutcome.keepDate:
      AppUndo.show(
        context,
        message:
            'In coda amministrativa: tiene la sua data '
            '(${adminDateLabel(result.date!)}), prima del prossimo slot',
        undo: () => controller.undo([result.before!]),
      );
  }
}

/// «In attesa fino a…»: blocked by someone else, with a check date.
Future<void> setAdminWaiting(
  BuildContext context,
  AdminSessionsController controller,
  Task task,
) async {
  final today = controller.today;
  final date = await showDatePicker(
    context: context,
    initialDate: today.addDays(7).asLocalDate,
    firstDate: today.asLocalDate,
    lastDate: today.addDays(366).asLocalDate,
    helpText: 'Quando ricontrollare?',
  );
  if (date == null || !context.mounted) return;
  final before = await controller.setWaiting(
    task,
    CivilDate.fromDateTime(date),
  );
  if (!context.mounted || before == null) return;
  AppUndo.show(
    context,
    message:
        'In attesa: ricontrolla ${adminDateLabel(CivilDate.fromDateTime(date))}',
    undo: () => controller.undo([before]),
  );
}

/// Origin and external id (for future imports). Generic titles only.
Future<void> editAdminSource(
  BuildContext context,
  AdminSessionsController controller,
  Task task,
) async {
  if (!canSetAdminSource(task.externalSource)) {
    _say(context, 'Attività importata da Todoist: l’origine resta Todoist.');
    return;
  }
  var source = AdminSource.fromStored(task.externalSource);
  final idController = TextEditingController(text: task.externalId ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Origine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<AdminSource?>(
              key: const ValueKey('admin-source'),
              value: source,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('Nessuna')),
                for (final value in AdminSource.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) => setDialogState(() => source = value),
            ),
            TextField(
              key: const ValueKey('admin-external-id'),
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'ID esterno (facoltativo)',
                helperText: 'Evita doppioni nelle importazioni future',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
  final externalId = idController.text;
  idController.dispose();
  if (saved != true || !context.mounted) return;
  try {
    await controller.setSource(task, source, externalId);
  } on FormatException catch (error) {
    if (context.mounted) _say(context, error.message);
  }
}
