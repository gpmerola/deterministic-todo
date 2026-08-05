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
    super.key,
  });

  final Task task;
  final TaskRepository repository;
  final bool showDateMetadata;
  final bool dense;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool confirmingCompletion = false;
  bool leavingAfterCompletion = false;

  Future<void> _setCompleted(bool completed) async {
    if (!completed) {
      await widget.repository.setCompleted(widget.task, false);
      return;
    }
    setState(() => confirmingCompletion = true);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) setState(() => leavingAfterCompletion = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await widget.repository.setCompleted(widget.task, true);
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    key: ValueKey('completion-slide-${widget.task.id}'),
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeInCubic,
    offset: leavingAfterCompletion ? const Offset(0.12, 0) : Offset.zero,
    child: AnimatedOpacity(
      key: ValueKey('completion-opacity-${widget.task.id}'),
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeInCubic,
      opacity: leavingAfterCompletion ? 0 : 1,
      child: Dismissible(
        key: ValueKey('dismiss-${widget.task.id}'),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {DismissDirection.endToStart: 0.62},
        movementDuration: const Duration(milliseconds: 110),
        resizeDuration: const Duration(milliseconds: 100),
        background: const SizedBox.shrink(),
        secondaryBackground: Container(
          color: Theme.of(context).colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
        onDismissed: (_) async {
          final messenger = ScaffoldMessenger.of(context);
          await widget.repository.softDelete(widget.task);
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Spostata nel cestino'),
              action: SnackBarAction(
                label: 'Annulla',
                onPressed: () => widget.repository.restore(widget.task),
              ),
            ),
          );
        },
        child: AnimatedContainer(
          key: ValueKey('task-surface-${widget.task.id}'),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: confirmingCompletion
                ? Colors.green.withValues(alpha: 0.10)
                : widget.task.priority == 1
                ? Colors.transparent
                : _priorityColor(widget.task.priority).withValues(alpha: 0.035),
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
            child: ListTile(
              dense: widget.dense,
              visualDensity: widget.dense
                  ? const VisualDensity(vertical: -2)
                  : null,
              leading: AnimatedScale(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                scale: confirmingCompletion ? 1.22 : 1,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: confirmingCompletion
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('completed-check'),
                          color: Colors.green,
                          size: 30,
                        )
                      : Checkbox(
                          key: const ValueKey('task-checkbox'),
                          value:
                              widget.task.status == TaskStatus.completed.name,
                          onChanged: (value) => _setCompleted(value ?? false),
                          activeColor: Colors.green,
                          side: BorderSide(
                            color: _priorityColor(widget.task.priority),
                            width: widget.task.priority == 1 ? 1.5 : 2.5,
                          ),
                        ),
                ),
              ),
              title: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: DefaultTextStyle.of(context).style.copyWith(
                  color: confirmingCompletion ? Colors.green.shade700 : null,
                  decoration: confirmingCompletion
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
                child: TodoistLinkText(widget.task.title),
              ),
              subtitle: _subtitle(widget.task),
              onTap: confirmingCompletion ? null : _showEditor,
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

  Future<void> _showEditor() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 45),
      reverseDuration: Duration(milliseconds: 25),
    ),
    builder: (_) =>
        TaskEditor(task: widget.task, repository: widget.repository),
  );
}
