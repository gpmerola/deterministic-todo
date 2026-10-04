import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import 'agenda_weeks_view.dart' show AgendaDayCell;

/// One whole month per screen, Monday first, like Google Calendar's month
/// view: rows share the available height so each day shows as many entries
/// as fit. Swipe up or down for the next or previous month. Days of the
/// neighbouring months complete the weeks, dimmed. Each month reads the
/// provider only when built.
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

  /// Changes whenever calendars, choices or the underlying data may differ.
  final int revision;
  final Future<List<AgendaDay>> Function(CivilDate first, int days) loadDays;

  /// Same days from this session's memory cache, or null; shown at once while
  /// [loadDays] revalidates.
  final List<AgendaDay>? Function(CivilDate first, int days) peekDays;
  final Map<String, Color?> colors;

  /// Opens the day view for a tapped cell.
  final ValueChanged<CivilDate> onOpenDay;
  final PageController? controller;

  static const monthsBack = 12;
  static const monthsAhead = 36;

  /// Monday on or before the 1st of [month]: where the grid starts.
  static CivilDate gridStart(CivilDate month) =>
      month.addDays(-(month.asLocalDate.weekday - DateTime.monday));

  /// 5 or 6 weeks: enough rows to hold the whole month.
  static int gridDays(CivilDate month) {
    final length = DateTime(month.year, month.month + 1, 0).day;
    final leading = month.asLocalDate.weekday - DateTime.monday;
    return ((leading + length) / 7).ceil() * 7;
  }

  @override
  State<AgendaMonthView> createState() => _AgendaMonthViewState();
}

class _AgendaMonthViewState extends State<AgendaMonthView> {
  late final PageController _ownController = PageController(
    initialPage: AgendaMonthView.monthsBack,
  );
  final Map<int, List<AgendaDay>> _months = {};
  final Set<int> _loading = {};
  final Set<int> _failed = {};

  /// Months shown from an older revision until their refetch completes, so a
  /// reload never blanks the grid.
  final Set<int> _stale = {};
  int _generation = 0;

  @override
  void dispose() {
    _ownController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgendaMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) {
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

  CivilDate _monthOf(int page) => CivilDate.fromDateTime(
    DateTime(
      widget.today.year,
      widget.today.month + page - AgendaMonthView.monthsBack,
      1,
    ),
  );

  Future<void> _fetch(int page) async {
    if (!_loading.add(page)) return;
    final generation = _generation;
    final month = _monthOf(page);
    try {
      final result = await widget.loadDays(
        AgendaMonthView.gridStart(month),
        AgendaMonthView.gridDays(month),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _months[page] = result;
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
    key: const PageStorageKey('agenda-months'),
    controller: widget.controller ?? _ownController,
    scrollDirection: Axis.vertical,
    itemCount: AgendaMonthView.monthsBack + AgendaMonthView.monthsAhead,
    itemBuilder: (context, page) {
      final month = _monthOf(page);
      var days = _months[page];
      if (days == null) {
        days = widget.peekDays(
          AgendaMonthView.gridStart(month),
          AgendaMonthView.gridDays(month),
        );
        if (days != null) _months[page] = days;
      }
      if ((days == null || _stale.contains(page)) && !_failed.contains(page)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_fetch(page));
        });
      }
      return AgendaMonthPage(
        month: month,
        today: widget.today,
        days: days ?? const [],
        colors: widget.colors,
        failed: _failed.contains(page),
        onDay: widget.onOpenDay,
      );
    },
  );
}

/// One month filling the available height.
class AgendaMonthPage extends StatelessWidget {
  const AgendaMonthPage({
    required this.month,
    required this.today,
    required this.days,
    required this.colors,
    required this.onDay,
    this.failed = false,
    super.key,
  });

  final CivilDate month;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onDay;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = AgendaMonthView.gridStart(month);
    final rows = AgendaMonthView.gridDays(month) ~/ 7;
    final byDate = {for (final day in days) day.date: day};
    final title = DateFormat('MMMM yyyy', 'it').format(month.asLocalDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Text(
            '${title[0].toUpperCase()}${title.substring(1)}'
            '${failed ? ' · impossibile leggere i calendari' : ''}',
            key: const ValueKey('agenda-month-title'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        const AgendaWeekdayHeader(),
        for (var row = 0; row < rows; row++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final date = start.addDays(row * 7 + column);
                        return AgendaDayCell(
                          date: date,
                          today: today,
                          entries: byDate[date]?.entries ?? const [],
                          colors: colors,
                          onDay: onDay,
                          outside: date.month != month.month,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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

/// "9" on the hour, otherwise "16:30": the shortest readable start.
String compactTime(DateTime moment) => moment.minute == 0
    ? '${moment.hour}'
    : '${moment.hour}:${moment.minute.toString().padLeft(2, '0')}';

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
            child: Text.rich(
              TextSpan(
                children: [
                  // Compact start time ("9", "16:30") at a glance, muted
                  // and smaller so the title keeps most of the width.
                  if (showTime)
                    TextSpan(
                      text: '${compactTime(entry.start)} ',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  TextSpan(text: title),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: style.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
