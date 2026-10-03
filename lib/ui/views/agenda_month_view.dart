import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';

/// Month grids scrolling vertically, Monday first, like Google Calendar's
/// month view. Each month reads the system provider only when it is built.
class AgendaMonthView extends StatefulWidget {
  const AgendaMonthView({
    required this.today,
    required this.revision,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpenDay,
    this.controller,
    super.key,
  });

  final CivilDate today;

  /// Changes whenever calendars, choices or the underlying data may differ;
  /// cached months are then dropped.
  final int revision;
  final Future<List<AgendaDay>> Function(CivilDate first, int days) loadDays;

  /// Same days from this session's memory cache, or null; shown at once while
  /// [loadDays] revalidates.
  final List<AgendaDay>? Function(CivilDate first, int days) peekDays;
  final Map<String, Color?> colors;

  /// Opens the day view for a tapped cell.
  final ValueChanged<CivilDate> onOpenDay;
  final ScrollController? controller;

  static const monthsBack = 12;
  static const monthsAhead = 36;
  static const maxChips = 3;

  @override
  State<AgendaMonthView> createState() => _AgendaMonthViewState();
}

class _AgendaMonthViewState extends State<AgendaMonthView> {
  static const _centerKey = ValueKey('agenda-month-center');
  final Map<int, List<AgendaDay>> _months = {};
  final Set<int> _loading = {};
  final Set<int> _failed = {};

  /// Months shown from an older revision until their refetch completes, so a
  /// reload never blanks the grid.
  final Set<int> _stale = {};
  int _generation = 0;

  @override
  void didUpdateWidget(covariant AgendaMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) {
      // Offsets are relative to today: nothing cached still lines up.
      _generation++;
      _months.clear();
      _stale.clear();
      _loading.clear();
      _failed.clear();
    } else if (oldWidget.revision != widget.revision) {
      _generation++;
      _stale.addAll(_months.keys);
      _loading.clear();
      _failed.clear();
    }
  }

  CivilDate _firstOf(int offset) => CivilDate.fromDateTime(
    DateTime(widget.today.year, widget.today.month + offset, 1),
  );

  Future<void> _fetch(int offset) async {
    if (!_loading.add(offset)) return;
    final generation = _generation;
    final first = _firstOf(offset);
    final days = DateTime(first.year, first.month + 1, 0).day;
    try {
      final result = await widget.loadDays(first, days);
      if (!mounted || generation != _generation) return;
      setState(() {
        _months[offset] = result;
        _stale.remove(offset);
        _loading.remove(offset);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed.add(offset);
        _loading.remove(offset);
      });
    }
  }

  Widget _month(BuildContext context, int offset) {
    var days = _months[offset];
    if (days == null) {
      final first = _firstOf(offset);
      days = widget.peekDays(
        first,
        DateTime(first.year, first.month + 1, 0).day,
      );
      if (days != null) _months[offset] = days;
    }
    final needsFetch = days == null || _stale.contains(offset);
    if (needsFetch && !_failed.contains(offset)) {
      // Fetch after this frame; the cell grid renders empty meanwhile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_fetch(offset));
      });
    }
    return AgendaMonthGrid(
      first: _firstOf(offset),
      today: widget.today,
      days: days ?? const [],
      colors: widget.colors,
      failed: _failed.contains(offset),
      onDay: (day) => widget.onOpenDay(day.date),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const AgendaWeekdayHeader(),
      Expanded(
        child: CustomScrollView(
          key: const PageStorageKey('agenda-months'),
          controller: widget.controller,
          center: _centerKey,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _month(context, -(index + 1)),
                childCount: AgendaMonthView.monthsBack,
              ),
            ),
            SliverList(
              key: _centerKey,
              delegate: SliverChildBuilderDelegate(
                (context, index) => _month(context, index),
                childCount: AgendaMonthView.monthsAhead,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class AgendaWeekdayHeader extends StatelessWidget {
  const AgendaWeekdayHeader({super.key});

  static const _labels = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          for (final label in _labels)
            Expanded(
              child: Text(label, textAlign: TextAlign.center, style: style),
            ),
        ],
      ),
    );
  }
}

/// One month: title and a Monday-first grid of [days] (already filtered).
class AgendaMonthGrid extends StatelessWidget {
  const AgendaMonthGrid({
    required this.first,
    required this.today,
    required this.days,
    required this.colors,
    required this.onDay,
    this.failed = false,
    super.key,
  });

  static const cellHeight = 92.0;

  final CivilDate first;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<AgendaDay> onDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = {for (final day in days) day.date: day};
    final count = DateTime(first.year, first.month + 1, 0).day;
    final leading = first.asLocalDate.weekday - 1;
    final rows = ((leading + count) / 7).ceil();
    final title = DateFormat('MMMM yyyy', 'it').format(first.asLocalDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            '${title[0].toUpperCase()}${title.substring(1)}'
            '${failed ? ' · impossibile leggere i calendari' : ''}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        for (var row = 0; row < rows; row++)
          SizedBox(
            height: cellHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _cell(
                      context,
                      row * 7 + column - leading + 1,
                      count,
                      byDate,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    int dayNumber,
    int count,
    Map<CivilDate, AgendaDay> byDate,
  ) {
    final theme = Theme.of(context);
    final border = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
      width: 0.5,
    );
    if (dayNumber < 1 || dayNumber > count) {
      return DecoratedBox(
        decoration: BoxDecoration(border: Border(top: border)),
      );
    }
    final date = CivilDate(first.year, first.month, dayNumber);
    final day = byDate[date] ?? AgendaDay(date, const []);
    final isToday = date == today;
    final isPast = date.compareTo(today) < 0;
    final entries = day.entries;
    final shown = entries.length > AgendaMonthView.maxChips
        ? AgendaMonthView.maxChips - 1
        : entries.length;
    return InkWell(
      key: ValueKey('agenda-day-$date'),
      onTap: () => onDay(day),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: border)),
        child: Opacity(
          opacity: isPast ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 3, 1, 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '$dayNumber',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: isToday ? FontWeight.w800 : null,
                        color: isToday ? theme.colorScheme.onPrimary : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                for (final entry in entries.take(shown))
                  AgendaChip(
                    entry: entry,
                    color:
                        colors[entry.calendarIds.first] ??
                        theme.colorScheme.primary,
                  ),
                if (entries.length > shown)
                  Text(
                    '+${entries.length - shown}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry in a grid cell, Google Calendar style: all-day events are
/// filled with their calendar colour, timed events are a coloured dot and
/// the title (so the title gets the whole width), Todo tasks a checkbox.
class AgendaChip extends StatelessWidget {
  const AgendaChip({
    required this.entry,
    required this.color,
    this.showTime = false,
    super.key,
  });

  /// Prefixes the start time of timed events (only where space allows).
  final bool showTime;

  final AgendaEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = entry.title.isEmpty ? '(senza titolo)' : entry.title;
    const style = TextStyle(fontSize: 10, height: 1.2);
    Widget text(String value, Color textColor, {bool strike = false}) => Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: style.copyWith(
        color: textColor,
        decoration: strike ? TextDecoration.lineThrough : null,
      ),
    );
    if (entry.isTask) {
      return Container(
        margin: const EdgeInsets.only(bottom: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary, width: 0.8),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(
              entry.completed
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 10,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 1),
            Expanded(
              child: text(
                title,
                theme.colorScheme.onSurface,
                strike: entry.completed,
              ),
            ),
          ],
        ),
      );
    }
    if (entry.allDay) {
      return Container(
        margin: const EdgeInsets.only(bottom: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: text(
          title,
          color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 1.5, top: 1),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 2, left: 1),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: text(
              showTime
                  ? '${DateFormat.Hm('it').format(entry.start)} $title'
                  : title,
              theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
