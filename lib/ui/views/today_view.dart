import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../domain/task.dart';

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
    final daily = <Task>[];
    for (final task in tasks) {
      if (task.recurrence == everyDayRecurrence) {
        daily.add(task);
      } else if (task.showDate != null && task.showDate!.compareTo(today) < 0) {
        overdue.add(task);
      } else {
        current.add(task);
      }
    }
    // Null entries are presentation markers, never persisted positions.
    final rows = <Task?>[
      if (overdue.isNotEmpty) null,
      ...overdue,
      if (overdue.isNotEmpty && (current.isNotEmpty || daily.isNotEmpty)) null,
      ...current,
      if (current.isNotEmpty && daily.isNotEmpty) null,
      ...daily,
    ];
    return ListView.builder(
      key: const PageStorageKey('task-list-today'),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      itemBuilder: (_, index) {
        final task = rows[index];
        if (task != null) return tileBuilder(task);
        if (index == 0 && overdue.isNotEmpty) {
          return const _GroupHeader(
            key: ValueKey('today-group-overdue'),
            label: 'Arretrate',
            overdue: true,
          );
        }
        if (overdue.isNotEmpty && index == overdue.length + 1) {
          return const _GroupHeader(
            key: ValueKey('today-group-current'),
            label: 'Oggi',
          );
        }
        return const Padding(
          key: ValueKey('today-daily-divider'),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Divider(height: 1),
        );
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
