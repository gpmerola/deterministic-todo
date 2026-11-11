import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../domain/task.dart';
import '../../services/evening_routine.dart';

/// Today: overdue items under their own header, then today's and Inbox items.
/// [tasks] are already filtered by SQL and ordered.
class TodayTaskList extends StatefulWidget {
  const TodayTaskList({
    required this.tasks,
    required this.today,
    required this.tileBuilder,
    this.database,
    super.key,
  });

  final AppDatabase? database;
  final List<Task> tasks;
  final String today;
  final Widget Function(Task task) tileBuilder;

  @override
  State<TodayTaskList> createState() => _TodayTaskListState();
}

class _TodayTaskListState extends State<TodayTaskList> {
  late Stream<Set<String>>? flags = widget.database == null
      ? null
      : EveningRoutine(widget.database!).watch();

  @override
  void didUpdateWidget(covariant TodayTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database) {
      flags = widget.database == null
          ? null
          : EveningRoutine(widget.database!).watch();
    }
  }

  @override
  Widget build(BuildContext context) => flags == null
      ? _list(const {})
      : StreamBuilder<Set<String>>(
          stream: flags,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            // If preferences cannot be read, keep every task accessible.
            return _list(snapshot.data ?? const {});
          },
        );

  Widget _list(Set<String> eveningIds) {
    final tasks = widget.tasks;
    final today = widget.today;
    final tileBuilder = widget.tileBuilder;
    final evening = <Task>[];
    final overdue = <Task>[];
    final current = <Task>[];
    final daily = <Task>[];
    for (final task in tasks) {
      if (eveningIds.contains(EveningRoutine.identity(task))) {
        evening.add(task);
      } else if (task.recurrence == everyDayRecurrence) {
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
      itemCount: rows.length + (evening.isEmpty ? 0 : 1),
      itemBuilder: (_, index) {
        if (index == rows.length) {
          return ExpansionTile(
            key: PageStorageKey('evening-routine-$today'),
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Routine serale'),
            subtitle: Text('${evening.length} attività'),
            children: [for (final task in evening) tileBuilder(task)],
          );
        }
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
