import 'package:flutter/material.dart';

import '../../data/local/database.dart';

/// Today: overdue items under their own header, then today's and Inbox items.
/// [tasks] are already filtered by SQL and ordered.
class TodayTaskList extends StatelessWidget {
  const TodayTaskList({
    required this.tasks,
    required this.today,
    required this.tileBuilder,
    super.key,
  });

  final List<Task> tasks;
  final String today;
  final Widget Function(Task task) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final overdue = <Task>[];
    final current = <Task>[];
    for (final task in tasks) {
      if (task.showDate != null && task.showDate!.compareTo(today) < 0) {
        overdue.add(task);
      } else {
        current.add(task);
      }
    }
    if (overdue.isEmpty) {
      return ListView.builder(
        key: const PageStorageKey('task-list-today'),
        // Room for the + button over the last row (UI review, build 218).
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: current.length,
        itemBuilder: (_, index) => tileBuilder(current[index]),
      );
    }
    final currentHeaderIndex = overdue.length + 1;
    final itemCount =
        currentHeaderIndex + (current.isEmpty ? 0 : 1) + current.length;
    return ListView.builder(
      key: const PageStorageKey('task-list-today'),
      // Room for the + button over the last row (UI review, build 218).
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: itemCount,
      itemBuilder: (_, index) {
        if (index == 0) {
          return const _GroupHeader(
            key: ValueKey('today-group-overdue'),
            label: 'Arretrate',
            overdue: true,
          );
        }
        if (index <= overdue.length) return tileBuilder(overdue[index - 1]);
        if (current.isNotEmpty && index == currentHeaderIndex) {
          return const _GroupHeader(
            key: ValueKey('today-group-current'),
            label: 'Oggi',
          );
        }
        return tileBuilder(current[index - currentHeaderIndex - 1]);
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, this.overdue = false, super.key});
  final String label;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: overdue ? colors.error : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: overdue ? colors.error.withValues(alpha: 0.28) : null,
            ),
          ),
        ],
      ),
    );
  }
}
