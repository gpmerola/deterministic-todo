import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local/database.dart';
import '../../domain/task.dart';

const _microMotion = Duration(milliseconds: 110);

/// Day-by-day timeline from [start], [days] at a time, empty days included.
/// [tasks] are already filtered by SQL to the same window.
class UpcomingTaskList extends StatelessWidget {
  const UpcomingTaskList({
    required this.tasks,
    required this.today,
    required this.start,
    required this.days,
    required this.onLoadMore,
    required this.tileBuilder,
    this.listKey,
    super.key,
  });

  /// Keys the scrollable: a new key restarts from the top, the same key
  /// restores the position after returning from a task.
  final Key? listKey;
  final List<Task> tasks;
  final CivilDate today;
  final CivilDate start;
  final int days;
  final VoidCallback onLoadMore;
  final Widget Function(Task task) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Task>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(task.showDate!, () => []).add(task);
    }
    final lastDate = CivilDate(today.year + 10, 12, 31);
    final dayCount = lastDate.asLocalDate.difference(start.asLocalDate).inDays;
    final visibleDays = days < dayCount + 1 ? days : dayCount + 1;
    return ListView.builder(
      key: listKey,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: visibleDays + 1,
      itemBuilder: (context, index) {
        if (index == visibleDays) {
          return days > dayCount
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    key: const ValueKey('upcoming-load-more'),
                    onPressed: onLoadMore,
                    child: const Text('Mostra altri 30 giorni'),
                  ),
                );
        }
        final date = start.addDays(index);
        final dateTasks = grouped[date.toString()] ?? const <Task>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
              child: Text(
                _friendlyDate(date),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (dateTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Nessuna attività',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final task in dateTasks) tileBuilder(task),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  static String _friendlyDate(CivilDate date) {
    final label = DateFormat('EEEE d MMMM', 'it').format(date.asLocalDate);
    return label[0].toUpperCase() + label.substring(1);
  }
}

/// "Vai a data": jumps the timeline to a chosen future day.
class UpcomingDateJump extends StatelessWidget {
  const UpcomingDateJump({
    required this.today,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final CivilDate today;
  final CivilDate? selected;
  final ValueChanged<CivilDate> onSelected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 2),
      child: TextButton.icon(
        key: const ValueKey('jump-to-future-date'),
        onPressed: () => _pick(context),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: AnimatedSwitcher(
          duration: _microMotion,
          child: Text(
            selected == null
                ? 'Vai a data'
                : DateFormat('d MMM yyyy', 'it').format(selected!.asLocalDate),
            key: ValueKey(selected?.toString() ?? 'jump-to-date'),
          ),
        ),
      ),
    ),
  );

  Future<void> _pick(BuildContext context) async {
    final tomorrow = today.addDays(1).asLocalDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: selected?.asLocalDate ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'Vai rapidamente a una data',
    );
    if (picked != null) onSelected(CivilDate.fromDateTime(picked));
  }
}
