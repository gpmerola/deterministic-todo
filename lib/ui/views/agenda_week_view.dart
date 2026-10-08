import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_visit_groups.dart';
import '../../domain/task.dart';
import 'agenda_colors.dart';
import 'agenda_day_view.dart';
import 'agenda_month_view.dart';
import 'agenda_weeks_view.dart' show mondayOf;
import 'agenda_word_wrap.dart';
import 'calendar_visit_group.dart';

/// Day columns with hours to scale, like Google Calendar's week view: free
/// slots are visible at a glance. Seven days from Monday, or [dayCount] = 3
/// from today (wider columns: titles and times readable on a phone). Swipe
/// sideways for the previous or next page; each page reads the provider
/// when built.
class AgendaWeekView extends StatefulWidget {
  const AgendaWeekView({
    this.dayCount = 7,
    required this.today,
    required this.revision,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpenDay,
    required this.onOpen,
    this.onLongPress,
    this.onCreate,
    this.controller,
    this.onPeriodChanged,
    this.now,
    super.key,
  });

  /// Quick actions on long press; null: none.
  final Future<void> Function(AgendaEntry entry)? onLongPress;

  /// 7 (week from Monday) or 3 (from today).
  final int dayCount;
  final CivilDate today;
  final int revision;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final Future<void> Function(AgendaEntry entry) onOpen;

  /// Null where events are read-only (the web mirror).
  final AgendaCreateAt? onCreate;
  final PageController? controller;
  final ValueChanged<CivilDate>? onPeriodChanged;
  final DateTime Function()? now;

  static const weeksBack = 130;
  static const weeksAhead = 400;
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

  /// First day of [page]: Mondays for the week, today ± 3n for 3 days.
  CivilDate _mondayOf(int page) => widget.dayCount == 7
      ? mondayOf(widget.today).addDays((page - AgendaWeekView.weeksBack) * 7)
      : widget.today.addDays(
          (page - AgendaWeekView.weeksBack) * widget.dayCount,
        );

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
      final result = await widget.loadDays(_mondayOf(page), widget.dayCount);
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
    onPageChanged: (index) => widget.onPeriodChanged?.call(_mondayOf(index)),
    key: const PageStorageKey('agenda-week'),
    controller: widget.controller ?? _ownController,
    itemCount: AgendaWeekView.weeksBack + AgendaWeekView.weeksAhead,
    itemBuilder: (context, page) {
      final monday = _mondayOf(page);
      var days = _weeks[page];
      if (days == null) {
        days = widget.peekDays(monday, widget.dayCount);
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
        dayCount: widget.dayCount,
        today: widget.today,
        days: days ?? const [],
        colors: widget.colors,
        onOpenDay: widget.onOpenDay,
        onOpen: widget.onOpen,
        onLongPress: widget.onLongPress,
        onCreate: widget.onCreate,
        now: widget.now ?? DateTime.now,
      );
    },
  );
}

class AgendaWeekPage extends StatefulWidget {
  const AgendaWeekPage({
    required this.monday,
    this.dayCount = 7,
    required this.today,
    required this.days,
    required this.colors,
    required this.onOpenDay,
    required this.onOpen,
    required this.onCreate,
    required this.now,
    this.onLongPress,
    super.key,
  });

  final Future<void> Function(AgendaEntry entry)? onLongPress;

  /// First day shown (a Monday in the week view).
  final CivilDate monday;
  final int dayCount;
  final CivilDate today;
  final List<AgendaDay> days;
  final Map<String, Color?> colors;
  final ValueChanged<CivilDate> onOpenDay;
  final Future<void> Function(AgendaEntry entry) onOpen;
  final AgendaCreateAt? onCreate;
  final DateTime Function() now;

  @override
  State<AgendaWeekPage> createState() => _AgendaWeekPageState();
}

class _AgendaWeekPageState extends State<AgendaWeekPage> {
  static const _gutter = 36.0;
  static const _hour = AgendaWeekView.hourHeight;
  ScrollController? _scroll;

  /// Press-and-drag on free time (build 221).
  CivilDate? _dragDate;
  int? _pressed;
  ({int start, int end})? _drag;

  /// Hours of the page, shared by all its columns so they line up; empty
  /// night hours are folded.
  TimelineScale scale = TimelineScale.forBlocks(const [], hourHeight: _hour);

  /// Around now in the current week, otherwise from 07:30.
  ScrollController get scroll => _scroll ??= ScrollController(
    initialScrollOffset: scale.y(
      _containsToday ? math.max(0, widget.now().hour - 1) * 60 : 7 * 60 + 30,
    ),
  );

  bool get _containsToday {
    final offset = widget.today.asLocalDate
        .difference(widget.monday.asLocalDate)
        .inDays;
    return offset >= 0 && offset < widget.dayCount;
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = {for (final day in widget.days) day.date: day};
    final dates = [
      for (var i = 0; i < widget.dayCount; i++) widget.monday.addDays(i),
    ];
    final itemsByDate = {
      for (final date in dates)
        date: calendarVisitItems(byDate[date]?.entries ?? const [], date),
    };
    final blocksByDate = {
      for (final date in dates)
        date: layoutDayTimeline(
          itemsByDate[date]!.map((item) => item.timelineEntry).toList(),
          date,
          minMinutes: 25,
        ),
    };
    scale = TimelineScale.forBlocks(
      blocksByDate.values.expand((blocks) => blocks),
      hourHeight: _hour,
    );
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
        ColoredBox(
          color: agendaDateHeaderFill(theme.colorScheme),
          child: Row(
            children: [
              const SizedBox(width: _gutter),
              for (final date in dates)
                Expanded(child: _dayHeader(context, date)),
            ],
          ),
        ),
        if (allDayRows > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: _gutter),
              for (var i = 0; i < dates.length; i++)
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
              height: scale.total,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var hour = 1; hour < 24; hour++)
                          if (!scale.isFolded(hour) ||
                              !scale.isFolded(hour - 1))
                            Positioned(
                              top: scale.y(hour * 60) - 7,
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
                        blocksByDate[date]!,
                        {
                          for (final item in itemsByDate[date]!)
                            if (item.grouped) item.first.instanceId: item,
                        },
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
    List<TimelineBlock> blocks,
    Map<String, CalendarVisitItem> groups,
  ) {
    final theme = Theme.of(context);
    final clashing = agendaOverlaps(entries).keys.toSet();
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
              if (widget.onCreate != null)
                Positioned.fill(
                  child: GestureDetector(
                    key: ValueKey('agenda-week-free-$date'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final minutes = scale.minuteAt(details.localPosition.dy);
                      final slot = (minutes ~/ 30 * 30).clamp(0, 23 * 60 + 30);
                      unawaited(
                        widget.onCreate!(
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
                    onLongPressStart: (details) => setState(() {
                      _dragDate = date;
                      _pressed = scale.minuteAt(details.localPosition.dy);
                      _drag = dragSpan(_pressed!, _pressed! + 60);
                    }),
                    onLongPressMoveUpdate: (details) => setState(() {
                      _drag = dragSpan(
                        _pressed!,
                        scale.minuteAt(details.localPosition.dy),
                      );
                    }),
                    onLongPressEnd: (_) {
                      final span = _drag;
                      setState(() {
                        _dragDate = null;
                        _pressed = null;
                        _drag = null;
                      });
                      if (span == null) return;
                      DateTime at(int minute) => DateTime(
                        date.year,
                        date.month,
                        date.day,
                        minute ~/ 60,
                        minute % 60,
                      );
                      unawaited(
                        widget.onCreate!(at(span.start), end: at(span.end)),
                      );
                    },
                    onLongPressCancel: () => setState(() {
                      _dragDate = null;
                      _pressed = null;
                      _drag = null;
                    }),
                  ),
                ),
              for (var hour = 0; hour < 24; hour++)
                if (scale.isFolded(hour))
                  Positioned(
                    top: scale.y(hour * 60),
                    height: scale.hourHeights[hour],
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.03,
                        ),
                      ),
                    ),
                  ),
              for (var hour = 1; hour < 24; hour++)
                Positioned(
                  top: scale.y(hour * 60),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(height: 0.5, color: line),
                  ),
                ),
              for (final block in blocks)
                Positioned(
                  key: ValueKey('agenda-week-block-${block.entry.instanceId}'),
                  top: scale.y(block.startMinute) + 0.5,
                  height:
                      scale.y(block.endMinute) - scale.y(block.startMinute) - 1,
                  left: timelineSlot(block, width).left + 0.5,
                  width: timelineSlot(block, width).width - 1,
                  child: groups[block.entry.instanceId] != null
                      ? CalendarVisitGroup(
                          item: groups[block.entry.instanceId]!,
                          color:
                              widget.colors[block.entry.calendarIds.first] ??
                              theme.colorScheme.primary,
                          onOpen: widget.onOpen,
                        )
                      : _block(
                          context,
                          block.entry,
                          widget.colors[block.entry.calendarIds.first] ??
                              theme.colorScheme.primary,
                          clash: clashing.contains(block.entry.instanceId),
                        ),
                ),
              if (_dragDate == date && _drag != null)
                Positioned(
                  key: ValueKey('agenda-week-drag-$date'),
                  top: scale.y(_drag!.start),
                  height: scale.y(_drag!.end) - scale.y(_drag!.start),
                  left: 0.5,
                  right: 0.5,
                  child: AgendaDragGhost(span: _drag!),
                ),
              if (date == widget.today)
                Positioned(
                  top: () {
                    final now = widget.now();
                    return scale.y(now.hour * 60 + now.minute) - 1;
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

  Widget _block(
    BuildContext context,
    AgendaEntry entry,
    Color color, {
    bool clash = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fill = agendaEventFill(color, scheme);
    // Unanswered invitations: outlined, not filled, like Google Calendar.
    final outlined = entry.unanswered;
    final onColor = outlined ? scheme.onSurface : agendaOnFill(fill);
    return Material(
      color: outlined ? scheme.surface : fill,
      // Overlapping another timed event: outlined in the error colour.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: clash
            ? BorderSide(color: scheme.error, width: 1.5)
            : outlined
            ? BorderSide(color: fill, width: 1.5)
            : BorderSide(color: agendaAccentText(color, scheme), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(widget.onOpen(entry)),
        onLongPress: widget.onLongPress == null
            ? null
            : () => unawaited(widget.onLongPress!(entry)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 1, 1, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 90;
              final style = TextStyle(
                color: onColor,
                fontSize: wide ? 11 : 9.5,
                height: 1.15,
              );
              final title = AgendaWordWrap(
                entry.title.isEmpty ? '(senza titolo)' : entry.title,
                style: style.copyWith(fontWeight: FontWeight.w600),
              );
              // The start time, when the block has room for it: times
              // must read at a glance (user request, build 220).
              if (constraints.maxHeight < 30) return title;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    // The whole span where the block is wide (3 days).
                    wide
                        ? '${compactTime(entry.start)}–'
                              '${compactTime(entry.end)}'
                        : compactTime(entry.start),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: style.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: wide ? 10.5 : 9,
                    ),
                  ),
                  Expanded(child: title),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
