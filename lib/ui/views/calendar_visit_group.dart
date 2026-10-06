import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_visit_groups.dart';
import 'agenda_colors.dart';

/// Three compact lines preserve full times even in narrow seven-column grids.
class CalendarVisitGroup extends StatelessWidget {
  const CalendarVisitGroup({
    required this.item,
    required this.color,
    required this.onOpen,
    super.key,
  });
  static const height = 39.0;
  final CalendarVisitItem item;
  final Color color;
  final Future<void> Function(AgendaEntry) onOpen;

  Future<void> _expand(BuildContext context) async {
    final selected = await showModalBottomSheet<AgendaEntry>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: Column(
            children: [
              Text(
                '${item.entries.length} visite',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              Text(DateFormat('EEEE d MMMM', 'it').format(item.first.start)),
              Expanded(
                child: ListView.builder(
                  itemCount: item.entries.length,
                  itemBuilder: (_, i) {
                    final entry = item.entries[i];
                    return ListTile(
                      title: Text(entry.title),
                      subtitle: Text(
                        '${_time(entry.start)} – ${_time(entry.end)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, entry),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) await onOpen(selected);
  }

  static String _time(DateTime value) => DateFormat('HH:mm').format(value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label:
          '${item.entries.length} visite, dalle ${_time(item.first.start)} '
          'alle ${_time(item.end)}. Tocca per espandere.',
      child: InkWell(
        key: ValueKey('calendar-visit-group-${item.first.instanceId}'),
        onTap: () => _expand(context),
        child: Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: agendaEventFill(color, scheme).withValues(alpha: 0.16),
            border: Border(left: BorderSide(color: color, width: 2)),
            borderRadius: BorderRadius.circular(2),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 180) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_time(item.first.start)}–${_time(item.end)} · ${item.entries.length} visite',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                );
              }
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_time(item.first.start)}–',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: agendaAccentText(color, scheme),
                        ),
                      ),
                      Text(
                        _time(item.end),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: agendaAccentText(color, scheme),
                        ),
                      ),
                      Text(
                        '${item.entries.length} visite',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
