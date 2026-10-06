import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_visit_groups.dart';
import '../../domain/task.dart';
import 'agenda_colors.dart';
import 'agenda_day_view.dart';
import 'agenda_month_view.dart';
import 'calendar_visit_group.dart';

/// Monday of the week containing [day].
CivilDate mondayOf(CivilDate day) =>
    day.addDays(-(day.asLocalDate.weekday - DateTime.monday));

/// Two or four Monday-first weeks. Each page reads only its visible range.
class AgendaWeeksView extends StatefulWidget {
  const AgendaWeeksView({
    required this.today,
    required this.revision,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpenDay,
    this.weekCount = 2,
    this.onOpenEntry,
    this.controller,
    this.onPeriodChanged,
    super.key,
  });

  final Future<void> Function(AgendaEntry)? onOpenEntry;
  final int weekCount;
  int get pageDays => weekCount * 7;

  final CivilDate today;
  final int revision;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final PageController? controller;
  final ValueChanged<CivilDate>? onPeriodChanged;

  static const pagesBack = 26;
  static const pagesAhead = 78;

  @override
  State<AgendaWeeksView> createState() => _AgendaWeeksViewState();
}

class _AgendaWeeksViewState extends State<AgendaWeeksView> {
  /// Starts on the current week when no controller is given.
  late final PageController _ownController = PageController(
    initialPage: AgendaWeeksView.pagesBack,
  );
  final Map<int, List<AgendaDay>> _pages = {};

  @override
  void dispose() {
    _ownController.dispose();
    super.dispose();
  }

  final Set<int> _loading = {};
  final Set<int> _failed = {};
  final Set<int> _stale = {};
  int _generation = 0;

  CivilDate _firstOf(int page) => mondayOf(
    widget.today,
  ).addDays((page - AgendaWeeksView.pagesBack) * widget.pageDays);

  @override
  void didUpdateWidget(covariant AgendaWeeksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) {
      _generation++;
      _pages.clear();
      _stale.clear();
      _loading.clear();
      _failed.clear();
    } else if (oldWidget.revision != widget.revision) {
      // Keep showing the old weeks until its refetch lands.
      _generation++;
      _stale.addAll(_pages.keys);
      _loading.clear();
      _failed.clear();
    }
  }

  Future<void> _fetch(int page) async {
    if (!_loading.add(page)) return;
    final generation = _generation;
    try {
      final result = await widget.loadDays(_firstOf(page), widget.pageDays);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pages[page] = result;
        _stale.remove(page);
        _loading.remove(page);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed.add(page);
        _loading.remove(page);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    onPageChanged: (index) => widget.onPeriodChanged?.call(_firstOf(index)),
    key: const PageStorageKey('agenda-weeks'),
    controller: widget.controller ?? _ownController,
    // Sideways, like the week and day views (build 206).
    itemCount: AgendaWeeksView.pagesBack + AgendaWeeksView.pagesAhead,
    itemBuilder: (context, page) {
      final first = _firstOf(page);
      var days = _pages[page];
      if (days == null) {
        days = widget.peekDays(first, widget.pageDays);
        if (days != null) _pages[page] = days;
      }
      if ((days == null || _stale.contains(page)) && !_failed.contains(page)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_fetch(page));
        });
      }
      return AgendaWeeksPage(
        onOpenEntry: widget.onOpenEntry,
        weekCount: widget.weekCount,
        first: first,
        today: widget.today,
        days: days ?? const [],
        colors: widget.colors,
        failed: _failed.contains(page),
        onDay: widget.onOpenDay,
      );
    },
  );
}

/// Monday-first weeks filling the available height.
class AgendaWeeksPage extends StatelessWidget {
  const AgendaWeeksPage({
    this.weekCount = 2,
    this.onOpenEntry,
    required this.first,
    required this.today,
    required this.days,
    required this.colors,
    required this.onDay,
    this.failed = false,
    super.key,
  });

  final Future<void> Function(AgendaEntry)? onOpenEntry;
  final int weekCount;
  final CivilDate first;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = first.addDays(weekCount * 7 - 1);
    final sameMonth = first.month == last.month;
    final range =
        '${DateFormat(sameMonth ? 'd' : 'd MMM', 'it').format(first.asLocalDate)}'
        ' – ${DateFormat(weekCount == 4 ? 'd MMM yyyy' : 'd MMMM yyyy', 'it').format(last.asLocalDate)}';
    final byDate = {for (final day in days) day.date: day};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Text(
            '$range${failed ? ' · impossibile leggere i calendari' : ''}',
            key: const ValueKey('agenda-fortnight-range'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        const AgendaWeekdayHeader(),
        for (var week = 0; week < weekCount; week++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: AgendaDayCell(
                      groupVisits: true,
                      onOpenEntry: onOpenEntry,
                      date: first.addDays(week * 7 + column),
                      today: today,
                      entries:
                          byDate[first.addDays(week * 7 + column)]?.entries ??
                          const [],
                      colors: colors,
                      onDay: onDay,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One day of a grid (2/4 weeks or month): number, then every entry that fits
/// the cell's height, the last slot becoming "+N". [outside] dims days of
/// the neighbouring month.
class AgendaDayCell extends StatelessWidget {
  const AgendaDayCell({
    required this.date,
    required this.today,
    required this.entries,
    required this.colors,
    required this.onDay,
    this.outside = false,
    this.groupVisits = false,
    this.onOpenEntry,
    super.key,
  });

  /// Height of one single-line entry (10 px text plus spacing).
  static const chipHeight = 15.0;

  /// How many [entries] fit in [height], keeping a line for "+N" when
  /// some are left out. Timed events take two lines (time over title).
  static int shownEntries(List<AgendaEntry> entries, double height) {
    return _shownHeights([
      for (final e in entries)
        e.allDay || e.isTask ? chipHeight : AgendaChip.twoLineHeight,
    ], height);
  }

  static int _shownHeights(List<double> heights, double available) {
    var used = 0.0;
    var fit = 0;
    for (final height in heights) {
      if (used + height > available) break;
      used += height;
      fit++;
    }
    if (fit == heights.length) return fit;
    while (fit > 0 && used + chipHeight > available) {
      used -= heights[--fit];
    }
    return fit;
  }

  final CivilDate date;
  final CivilDate today;
  final List<AgendaEntry> entries;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onDay;
  final bool outside;
  final bool groupVisits;
  final Future<void> Function(AgendaEntry)? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = date == today;
    final label = date.day == 1
        ? DateFormat('d MMM', 'it').format(date.asLocalDate)
        : '${date.day}';
    final dim = outside ? 0.35 : (date.compareTo(today) < 0 ? 0.6 : 1.0);
    final weekend = date.asLocalDate.weekday >= DateTime.saturday;
    return InkWell(
      key: ValueKey('agenda-day-$date'),
      onTap: () => onDay(date),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Light weekend tint to find your way around the grid faster.
          color: weekend
              ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
              : null,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
        ),
        child: Opacity(
          opacity: dim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final items = groupVisits
                    ? calendarVisitItems(entries, date)
                    : entries.map((e) => CalendarVisitItem([e])).toList();
                final shown = _shownHeights([
                  for (final item in items)
                    item.grouped
                        ? CalendarVisitGroup.height
                        : item.first.allDay || item.first.isTask
                        ? chipHeight
                        : AgendaChip.twoLineHeight,
                ], constraints.maxHeight - 19);
                final hiddenCount = items
                    .skip(shown)
                    .fold<int>(0, (sum, item) => sum + item.entries.length);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: agendaDateHeaderFill(theme.colorScheme),
                      child: Center(
                        child: Container(
                          height: 17,
                          constraints: const BoxConstraints(minWidth: 17),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          alignment: Alignment.center,
                          decoration: isToday
                              ? BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(9),
                                )
                              : null,
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                              fontWeight: isToday ? FontWeight.w800 : null,
                              color: isToday
                                  ? theme.colorScheme.onPrimary
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    for (final item in items.take(shown))
                      if (item.grouped)
                        CalendarVisitGroup(
                          item: item,
                          color:
                              colors[item.first.calendarIds.first] ??
                              theme.colorScheme.primary,
                          onOpen:
                              onOpenEntry ??
                              (_) async {
                                onDay(date);
                              },
                        )
                      else
                        AgendaChip(
                          entry: item.first,
                          twoLines: true,
                          day: date,
                          color:
                              colors[item.first.calendarIds.first] ??
                              theme.colorScheme.primary,
                        ),
                    if (hiddenCount > 0)
                      Text(
                        '+$hiddenCount',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
