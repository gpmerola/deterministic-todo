part of '../main.dart';

Color _priorityColor(int rawPriority) => switch (rawPriority) {
  4 => Colors.red,
  3 => Colors.orange,
  2 => Colors.blue,
  _ => Colors.grey,
};

class TaskTile extends StatefulWidget {
  const TaskTile({
    required this.task,
    required this.repository,
    this.showDateMetadata = true,
    this.dense = false,
    this.highlightRemote = false,
    this.onSelected,
    super.key,
  });

  final Task task;
  final TaskRepository repository;
  final bool showDateMetadata;
  final bool dense;
  final bool highlightRemote;
  final VoidCallback? onSelected;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool confirmingCompletion = false;
  bool leavingAfterCompletion = false;
  bool deleteThresholdFeedbackSent = false;

  Future<void> _setCompleted(bool completed) async {
    if (confirmingCompletion || leavingAfterCompletion) return;
    final elapsed = Stopwatch()..start();
    if (!completed) {
      await widget.repository.setCompleted(widget.task, false);
      elapsed.stop();
      return;
    }
    setState(() => confirmingCompletion = true);
    unawaited(HapticFeedback.lightImpact());
    // Keep the check visible without moving the row. Only after the user has
    // perceived the confirmation do the surrounding rows close the gap.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (mounted) setState(() => leavingAfterCompletion = true);
    await Future<void>.delayed(const Duration(milliseconds: 190));
    final nextDate = await widget.repository.setCompleted(widget.task, true);
    elapsed.stop();
    unawaited(
      DiagnosticLogService.instance.event(
        'interaction_latency',
        fields: {
          'interaction': 'task_complete',
          'outcome': 'success',
          'duration_ms': elapsed.elapsedMilliseconds,
        },
      ),
    );
    if (mounted) {
      AppUndo.show(
        context,
        message: nextDate == null
            ? 'Attività completata'
            : 'Completata · prossima: ${DateFormat('EEEE d MMMM yyyy', 'it').format(nextDate.asLocalDate)}',
        undo: () => widget.repository.undoCompletion(widget.task),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: taskAccessibilityLabel(widget.task),
    child: ClipRect(
      child: AnimatedAlign(
        key: ValueKey('completion-collapse-${widget.task.id}'),
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: leavingAfterCompletion ? 0 : 1,
        child: Dismissible(
          key: ValueKey('dismiss-${widget.task.id}'),
          direction: DismissDirection.endToStart,
          dismissThresholds: const {DismissDirection.endToStart: 0.72},
          movementDuration: const Duration(milliseconds: 220),
          resizeDuration: const Duration(milliseconds: 260),
          background: const SizedBox.shrink(),
          secondaryBackground: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cestino',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          onUpdate: (details) {
            if (details.progress >= 0.72 && !deleteThresholdFeedbackSent) {
              deleteThresholdFeedbackSent = true;
              unawaited(HapticFeedback.mediumImpact());
            } else if (details.progress < 0.12) {
              deleteThresholdFeedbackSent = false;
            }
          },
          onDismissed: (_) {
            final deletion = widget.repository.softDelete(widget.task);
            if (!context.mounted) return;
            AppUndo.show(
              context,
              message: 'Spostata nel cestino',
              undo: () async {
                await deletion;
                await widget.repository.restore(widget.task);
              },
            );
            unawaited(deletion);
          },
          child: AnimatedContainer(
            key: ValueKey('task-surface-${widget.task.id}'),
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: widget.highlightRemote
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.55)
                  : widget.task.priority == 1
                  ? Colors.transparent
                  : _priorityColor(
                      widget.task.priority,
                    ).withValues(alpha: 0.035),
              border: widget.task.priority == 1
                  ? null
                  : Border(
                      left: BorderSide(
                        color: _priorityColor(widget.task.priority),
                        width: 3,
                      ),
                    ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) =>
                    _showDesktopMenu(details.globalPosition),
                child: ListTile(
                  dense:
                      widget.dense || MediaQuery.sizeOf(context).width >= 900,
                  visualDensity:
                      widget.dense || MediaQuery.sizeOf(context).width >= 900
                      ? const VisualDensity(vertical: -2)
                      : null,
                  leading: GestureDetector(
                    key: const ValueKey('completion-no-swipe-zone'),
                    behavior: HitTestBehavior.opaque,
                    // A horizontal gesture that starts on the completion target
                    // belongs to this control, never to the parent Dismissible.
                    onHorizontalDragStart: (_) {},
                    child: Semantics(
                      label: 'Completa ${widget.task.title}',
                      child: Checkbox(
                        key: const ValueKey('task-checkbox'),
                        value:
                            confirmingCompletion ||
                            widget.task.status == TaskStatus.completed.name,
                        onChanged: (value) => _setCompleted(value ?? false),
                        shape: const CircleBorder(),
                        activeColor: Colors.green,
                        checkColor: Colors.white,
                        side: BorderSide(
                          color: _priorityColor(widget.task.priority),
                          width: widget.task.priority == 1 ? 1.5 : 2.5,
                        ),
                      ),
                    ),
                  ),
                  title: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    style: DefaultTextStyle.of(context).style.copyWith(
                      color: confirmingCompletion
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                      decoration: confirmingCompletion
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                    child: TodoistLinkText(widget.task.title),
                  ),
                  subtitle: _subtitle(widget.task),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Azioni attività',
                    onSelected: _runAction,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Modifica'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Cestino'),
                        ),
                      ),
                    ],
                  ),
                  onTap: confirmingCompletion
                      ? null
                      : widget.onSelected ?? _showEditor,
                  onLongPress: confirmingCompletion
                      ? null
                      : () => unawaited(_showMobileMenu()),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget? _subtitle(Task task) {
    final metadata = [
      if (widget.showDateMetadata && task.showDate != null)
        DateFormat(
          'd MMM',
          'it',
        ).format(CivilDate.parse(task.showDate!).asLocalDate),
      if (task.recurrence != null)
        '↻ ${recurrenceSmartLabel(task.recurrence, task.showDate)}',
    ];
    final notes = task.notes?.trim();
    if ((notes == null || notes.isEmpty) && metadata.isEmpty) return null;
    final secondaryStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notes != null && notes.isNotEmpty)
          TodoistLinkText(
            notes,
            style: secondaryStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (metadata.isNotEmpty)
          Text(metadata.join(' · '), style: secondaryStyle),
      ],
    );
  }

  Future<void> _showEditor() {
    final elapsed = Stopwatch()..start();
    var logged = false;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 45),
        reverseDuration: Duration(milliseconds: 25),
      ),
      builder: (_) {
        if (!logged) {
          logged = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            elapsed.stop();
            unawaited(
              DiagnosticLogService.instance.event(
                'interaction_latency',
                fields: {
                  'interaction': 'editor_open',
                  'outcome': 'visible',
                  'duration_ms': elapsed.elapsedMilliseconds,
                },
              ),
            );
          });
        }
        return TaskEditor(task: widget.task, repository: widget.repository);
      },
    );
  }

  Future<void> _runAction(String action) async {
    if (action == 'edit') return _showEditor();
    if (action == 'complete') {
      await _setCompleted(true);
    } else if (action == 'delete') {
      await widget.repository.softDelete(widget.task);
      if (!mounted) return;
      AppUndo.show(
        context,
        message: 'Spostata nel cestino',
        undo: () => widget.repository.restore(widget.task),
      );
    }
  }

  Future<void> _showDesktopMenu(Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Modifica')),
        PopupMenuItem(value: 'complete', child: Text('Completa')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Cestino')),
      ],
    );
    if (action != null) await _runAction(action);
  }

  Future<void> _showMobileMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 45),
        reverseDuration: Duration(milliseconds: 25),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifica'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Completa'),
              onTap: () => Navigator.pop(context, 'complete'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Cestino'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action != null) await _runAction(action);
  }
}

String taskAccessibilityLabel(Task task) {
  final details = <String>[
    task.title,
    'Priorità P${5 - task.priority}',
    if (task.showDate != null) 'Data ${task.showDate}',
    if (task.recurrence != null)
      'Ripetizione ${recurrenceSmartLabel(task.recurrence, task.showDate)}',
  ];
  return details.join(', ');
}
