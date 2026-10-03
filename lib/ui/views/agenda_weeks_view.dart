import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import 'agenda_day_view.dart';
import 'agenda_month_view.dart';

/// Monday of the week containing [day].
CivilDate mondayOf(CivilDate day) =>
    day.addDays(-(day.asLocalDate.weekday - DateTime.monday));

/// Default Agenda view: two weeks per screen, so each day has room for
/// several events with their start time. Swipe up or down for the next or
/// previous fortnight; each page reads the provider only when built.
class AgendaWeeksView extends StatefulWidget {
  const AgendaWeeksView({
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
  final int revision;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final PageController? controller;

  static const pagesBack = 26;
  static const pagesAhead = 78;
  static const days = 14;

  @override
  State<AgendaWeeksView> createState() => _AgendaWeeksViewState();
}

class _AgendaWeeksViewState extends State<AgendaWeeksView> {
  /// Starts on the current fortnight when no controller is given.
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
  ).addDays((page - AgendaWeeksView.pagesBack) * AgendaWeeksView.days);

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
      // Keep showing the old fortnight until its refetch lands.
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
      final result = await widget.loadDays(
        _firstOf(page),
        AgendaWeeksView.days,
      );
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
    key: const PageStorageKey('agenda-weeks'),
    controller: widget.controller ?? _ownController,
    scrollDirection: Axis.vertical,
    itemCount: AgendaWeeksView.pagesBack + AgendaWeeksView.pagesAhead,
    itemBuilder: (context, page) {
      final first = _firstOf(page);
      var days = _pages[page];
      if (days == null) {
        days = widget.peekDays(first, AgendaWeeksView.days);
        if (days != null) _pages[page] = days;
      }
      if ((days == null || _stale.contains(page)) && !_failed.contains(page)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_fetch(page));
        });
      }
      return AgendaFortnight(
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

/// Two Monday-first weeks filling the available height.
class AgendaFortnight extends StatelessWidget {
  const AgendaFortnight({
    required this.first,
    required this.today,
    required this.days,
    required this.colors,
    required this.onDay,
    this.failed = false,
    super.key,
  });

  static const chipHeight = 18.0;

  final CivilDate first;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = first.addDays(AgendaWeeksView.days - 1);
    final sameMonth = first.month == last.month;
    final range =
        '${DateFormat(sameMonth ? 'd' : 'd MMM', 'it').format(first.asLocalDate)}'
        ' – ${DateFormat('d MMMM yyyy', 'it').format(last.asLocalDate)}';
    final byDate = {for (final day in days) day.date: day};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(
            '$range${failed ? ' · impossibile leggere i calendari' : ''}',
            key: const ValueKey('agenda-fortnight-range'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const AgendaWeekdayHeader(),
        for (var week = 0; week < 2; week++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _cell(
                      context,
                      first.addDays(week * 7 + column),
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
    CivilDate date,
    Map<CivilDate, AgendaDay> byDate,
  ) {
    final theme = Theme.of(context);
    final entries = byDate[date]?.entries ?? const <AgendaEntry>[];
    final isToday = date == today;
    final label = date.day == 1
        ? DateFormat('d MMM', 'it').format(date.asLocalDate)
        : '${date.day}';
    return InkWell(
      key: ValueKey('agenda-day-$date'),
      onTap: () => onDay(date),
      child: DecoratedBox(
        decoration: BoxDecoration(
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
          opacity: date.compareTo(today) < 0 ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 3, 1, 1),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Every chip that fits; the last slot becomes "+N" if needed.
                final slots = math.max(
                  0,
                  ((constraints.maxHeight - 26) / chipHeight).floor(),
                );
                final shown = entries.length > slots
                    ? math.max(0, slots - 1)
                    : entries.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        height: 22,
                        constraints: const BoxConstraints(minWidth: 22),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: isToday
                            ? BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(11),
                              )
                            : null,
                        child: Text(
                          label,
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
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
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
