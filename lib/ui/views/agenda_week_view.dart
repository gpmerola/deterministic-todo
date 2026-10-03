import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import 'agenda_day_view.dart';
import 'agenda_month_view.dart';
import 'agenda_weeks_view.dart' show mondayOf;

/// Seven day columns with hours to scale, like Google Calendar's week view:
/// free slots across the week are visible at a glance. Swipe sideways for
/// the previous or next week; each week reads the provider when built.
class AgendaWeekView extends StatefulWidget {
  const AgendaWeekView({
    required this.today,
    required this.revision,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpenDay,
    required this.onOpen,
    required this.onCreate,
    this.controller,
    this.now,
    super.key,
  });

  final CivilDate today;
  final int revision;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final Future<void> Function(AgendaEntry entry) onOpen;
  final Future<void> Function(DateTime start) onCreate;
  final PageController? controller;
  final DateTime Function()? now;

  static const weeksBack = 52;
  static const weeksAhead = 156;
  static const hourHeight = 48.0;

  @override
  State<AgendaWeekView> createState() => _AgendaWeekViewState();
}

class _AgendaWeekViewState extends State<AgendaWeekView> {
  /// Starts on the current week when no controller is given.
  late final PageController _ownController = PageController(
    initialPage: AgendaWeekView.weeksBack,
  );
  final Map<int, List<AgendaDay>> _weeks = {};

  @override
  void dispose() {
    _ownController.dispose();
    super.dispose();
  }

  final Set<int> _loading = {};
  final Set<int> _failed = {};
  final Set<int> _stale = {};
  int _generation = 0;

  CivilDate _mondayOf(int page) =>
      mondayOf(widget.today).addDays((page - AgendaWeekView.weeksBack) * 7);

  @override
  void didUpdateWidget(covariant AgendaWeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) {
      _generation++;
      _weeks.clear();
      _stale.clear();
      _loading.clear();
      _failed.clear();
    } else if (oldWidget.revision != widget.revision) {
      _generation++;
      _stale.addAll(_weeks.keys);
      _loading.clear();
      _failed.clear();
    }
  }

  Future<void> _fetch(int page) async {
    if (!_loading.add(page)) return;
    final generation = _generation;
    try {
      final result = await widget.loadDays(_mondayOf(page), 7);
      if (!mounted || generation != _generation) return;
      setState(() {
        _weeks[page] = result;
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
    key: const PageStorageKey('agenda-week'),
    controller: widget.controller ?? _ownController,
    itemCount: AgendaWeekView.weeksBack + AgendaWeekView.weeksAhead,
    itemBuilder: (context, page) {
      final monday = _mondayOf(page);
      var days = _weeks[page];
      if (days == null) {
        days = widget.peekDays(monday, 7);
        if (days != null) _weeks[page] = days;
      }
      if ((days == null || _stale.contains(page)) && !_failed.contains(page)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_fetch(page));
        });
      }
      return AgendaWeekPage(
        key: ValueKey('agenda-week-$monday'),
        monday: monday,
        today: widget.today,
        days: days ?? const [],
        colors: widget.colors,
        onOpenDay: widget.onOpenDay,
        onOpen: widget.onOpen,
        onCreate: widget.onCreate,
        now: widget.now ?? DateTime.now,
      );
    },
  );
}

class AgendaWeekPage extends StatefulWidget {
  const AgendaWeekPage({
    required this.monday,
    required this.today,
    required this.days,
    required this.colors,
    required this.onOpenDay,
    required this.onOpen,
    required this.onCreate,
    required this.now,
    super.key,
  });

  final CivilDate monday;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final Future<void> Function(AgendaEntry entry) onOpen;
  final Future<void> Function(DateTime start) onCreate;
  final DateTime Function() now;

  @override
  State<AgendaWeekPage> createState() => _AgendaWeekPageState();
}

class _AgendaWeekPageState extends State<AgendaWeekPage> {
  static const _gutter = 36.0;
  static const _hour = AgendaWeekView.hourHeight;
  late final ScrollController scroll = ScrollController(
    // Around now in the current week, otherwise from 07:30.
    initialScrollOffset: _containsToday
        ? math.max(0, widget.now().hour - 1) * _hour
        : 7.5 * _hour,
  );

  bool get _containsToday {
    final offset = widget.today.asLocalDate
        .difference(widget.monday.asLocalDate)
        .inDays;
    return offset >= 0 && offset < 7;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = {for (final day in widget.days) day.date: day};
    final dates = [for (var i = 0; i < 7; i++) widget.monday.addDays(i)];
    final allDay = [
      for (final date in dates)
        [
          for (final entry in byDate[date]?.entries ?? const <AgendaEntry>[])
            if (entry.allDay) entry,
        ],
    ];
    final allDayRows = math.min(
      2,
      allDay.fold(0, (rows, list) => math.max(rows, list.length)),
    );
    final last = dates.last;
    final title =
        '${DateFormat(widget.monday.month == last.month ? 'd' : 'd MMM', 'it').format(widget.monday.asLocalDate)}'
        ' – ${DateFormat('d MMMM yyyy', 'it').format(last.asLocalDate)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Text(
            title,
            key: const ValueKey('agenda-week-range'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        Row(
          children: [
            const SizedBox(width: _gutter),
            for (final date in dates)
              Expanded(child: _dayHeader(context, date)),
          ],
        ),
        if (allDayRows > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: _gutter),
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onOpenDay(dates[i]),
                    child: SizedBox(
                      height: allDayRows * 18.0 + 4,
                      child: Column(
                        children: [
                          for (final entry in allDay[i].take(
                            allDay[i].length > allDayRows
                                ? allDayRows - 1
                                : allDayRows,
                          ))
                            AgendaChip(
                              entry: entry,
                              color:
                                  widget.colors[entry.calendarIds.first] ??
                                  theme.colorScheme.primary,
                            ),
                          if (allDay[i].length > allDayRows)
                            Text(
                              '+${allDay[i].length - allDayRows + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 80,
            ),
            child: SizedBox(
              height: 24 * _hour,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var hour = 1; hour < 24; hour++)
                          Positioned(
                            top: hour * _hour - 7,
                            right: 4,
                            child: Text(
                              hour.toString().padLeft(2, '0'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final date in dates)
                    Expanded(
                      child: _column(
                        context,
                        date,
                        byDate[date]?.entries ?? const [],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayHeader(BuildContext context, CivilDate date) {
    final theme = Theme.of(context);
    final isToday = date == widget.today;
    final weekday = DateFormat('EEE', 'it').format(date.asLocalDate);
    return InkWell(
      key: ValueKey('agenda-week-day-$date'),
      onTap: () => widget.onOpenDay(date),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            Text(
              weekday[0].toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                '${date.day}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isToday ? theme.colorScheme.onPrimary : null,
                  fontWeight: isToday ? FontWeight.w800 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
    BuildContext context,
    CivilDate date,
    List<AgendaEntry> entries,
  ) {
    final theme = Theme.of(context);
    final blocks = layoutDayTimeline(entries, date, minMinutes: 25);
    final line = theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: line, width: 0.5)),
          ),
          child: Stack(
            children: [
              // Tapping free time creates an event at that half hour.
              Positioned.fill(
                child: GestureDetector(
                  key: ValueKey('agenda-week-free-$date'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final minutes = (details.localPosition.dy / _hour * 60)
                        .floor();
                    final slot = (minutes ~/ 30 * 30).clamp(0, 23 * 60 + 30);
                    unawaited(
                      widget.onCreate(
                        DateTime(
                          date.year,
                          date.month,
                          date.day,
                          slot ~/ 60,
                          slot % 60,
                        ),
                      ),
                    );
                  },
                ),
              ),
              for (var hour = 1; hour < 24; hour++)
                Positioned(
                  top: hour * _hour,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(height: 0.5, color: line),
                  ),
                ),
              for (final block in blocks)
                Positioned(
                  key: ValueKey('agenda-week-block-${block.entry.instanceId}'),
                  top: block.startMinute * _hour / 60 + 0.5,
                  height:
                      (block.endMinute - block.startMinute) * _hour / 60 - 1,
                  left: block.column * width / block.columns + 0.5,
                  width: width / block.columns - 1,
                  child: _block(
                    context,
                    block.entry,
                    widget.colors[block.entry.calendarIds.first] ??
                        theme.colorScheme.primary,
                  ),
                ),
              if (date == widget.today)
                Positioned(
                  top: () {
                    final now = widget.now();
                    return (now.hour * 60 + now.minute) * _hour / 60 - 1;
                  }(),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(height: 2, color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _block(BuildContext context, AgendaEntry entry, Color color) {
    final onColor = color.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(widget.onOpen(entry)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 1, 1, 0),
          child: Text(
            entry.title.isEmpty ? '(senza titolo)' : entry.title,
            overflow: TextOverflow.clip,
            style: TextStyle(color: onColor, fontSize: 9.5, height: 1.15),
          ),
        ),
      ),
    );
  }
}
