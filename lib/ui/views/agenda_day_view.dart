import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_visit_groups.dart';
import '../../domain/task.dart';
import 'agenda_colors.dart';
import 'agenda_view.dart' show AgendaTodayIcon;
import 'calendar_visit_group.dart';

typedef AgendaDaysLoader =
    Future<List<AgendaDay>> Function(CivilDate first, int days);
typedef AgendaDaysPeek = List<AgendaDay>? Function(CivilDate first, int days);

/// New event at [start]; [end] when dragged to a length, otherwise an hour.
typedef AgendaCreateAt = Future<void> Function(DateTime start, {DateTime? end});

/// Google Calendar-like day view: 24 hours to scale, so gaps between
/// meetings are visible; swipe for the previous or next day.
class AgendaDayPage extends StatefulWidget {
  const AgendaDayPage({
    required this.initialDay,
    required this.today,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpen,
    this.onLongPress,
    this.onCreate,
    this.zoneLabel,
    this.now,
    this.onDayChanged,
    super.key,
  });

  /// Quick actions on long press; null: none.
  final Future<void> Function(AgendaEntry entry)? onLongPress;

  /// Recognised device zone shown under the date; times are in it.
  final String? zoneLabel;

  /// New event starting at the given time; null where events are read-only
  /// (the web mirror).
  final AgendaCreateAt? onCreate;

  final ValueChanged<CivilDate>? onDayChanged;
  final CivilDate initialDay;
  final CivilDate today;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final Future<void> Function(AgendaEntry entry) onOpen;

  /// Clock for the current-time line; tests pass a fixed value.
  final DateTime Function()? now;

  static const hourHeight = 64.0;

  @override
  State<AgendaDayPage> createState() => _AgendaDayPageState();
}

class _AgendaDayPageState extends State<AgendaDayPage> {
  static const _origin = 10000;
  late final PageController pages = PageController(initialPage: _origin);
  late CivilDate shown = widget.initialDay;

  /// Bumped after a creation from the button, so pages reread their day.
  int _refresh = 0;

  CivilDate _dayAt(int index) => widget.initialDay.addDays(index - _origin);

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _step(int days) => unawaited(
    pages.animateToPage(
      (pages.page ?? _origin.toDouble()).round() + days,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    ),
  );

  void _goToToday() {
    final delta = widget.today.asLocalDate
        .difference(widget.initialDay.asLocalDate)
        .inDays;
    unawaited(
      pages.animateToPage(
        _origin + delta,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The year only when it differs: the full date is cut off on phones.
    final label = DateFormat(
      shown.year == widget.today.year ? 'EEE d MMMM' : 'EEE d MMM yyyy',
      'it',
    ).format(shown.asLocalDate);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label[0].toUpperCase() + label.substring(1)),
            Text(
              widget.zoneLabel ?? 'Fuso orario non riconosciuto',
              key: const ValueKey('agenda-day-zone'),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        // Compact actions: with "Oggi" as text and two full-size arrows the
        // date and the zone were cut ("Giovedì 2…", build 221).
        actions: [
          if (shown != widget.today)
            IconButton(
              key: const ValueKey('agenda-day-today'),
              tooltip: 'Oggi',
              visualDensity: VisualDensity.compact,
              onPressed: _goToToday,
              icon: AgendaTodayIcon(day: widget.today.day),
            ),
          // Swiping already moves between days; the arrows make it visible.
          IconButton(
            key: const ValueKey('agenda-day-previous'),
            tooltip: 'Giorno prima',
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const ValueKey('agenda-day-next'),
            tooltip: 'Giorno dopo',
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PageView.builder(
        controller: pages,
        onPageChanged: (index) {
          setState(() => shown = _dayAt(index));
          widget.onDayChanged?.call(shown);
        },
        itemBuilder: (context, index) => AgendaDayTimeline(
          key: ValueKey('agenda-timeline-${_dayAt(index)}-$_refresh'),
          day: _dayAt(index),
          today: widget.today,
          loadDays: widget.loadDays,
          peekDays: widget.peekDays,
          colors: widget.colors,
          onOpen: widget.onOpen,
          onLongPress: widget.onLongPress,
          onCreate: widget.onCreate,
          now: widget.now ?? DateTime.now,
        ),
      ),
      floatingActionButton: widget.onCreate == null
          ? null
          : FloatingActionButton(
              key: const ValueKey('agenda-day-new-event'),
              tooltip: 'Nuovo evento',
              onPressed: () {
                final now = (widget.now ?? DateTime.now)();
                final hour = shown == widget.today ? now.hour + 1 : 9;
                unawaited(
                  widget
                      .onCreate!(
                        DateTime(
                          shown.year,
                          shown.month,
                          shown.day,
                          hour.clamp(0, 23),
                        ),
                      )
                      .then((_) {
                        if (mounted) setState(() => _refresh++);
                      }),
                );
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}

class AgendaDayTimeline extends StatefulWidget {
  const AgendaDayTimeline({
    required this.day,
    required this.today,
    required this.loadDays,
    required this.peekDays,
    required this.colors,
    required this.onOpen,
    required this.onCreate,
    required this.now,
    this.onLongPress,
    super.key,
  });

  final Future<void> Function(AgendaEntry entry)? onLongPress;
  final AgendaCreateAt? onCreate;
  final CivilDate day;
  final CivilDate today;
  final AgendaDaysLoader loadDays;
  final AgendaDaysPeek peekDays;
  final Map<String, Color?> colors;
  final Future<void> Function(AgendaEntry entry) onOpen;
  final DateTime Function() now;

  @override
  State<AgendaDayTimeline> createState() => _AgendaDayTimelineState();
}

class _AgendaDayTimelineState extends State<AgendaDayTimeline> {
  static const _gutter = 48.0;
  AgendaDay? data;
  ScrollController? scroll;

  /// Press-and-drag on free time: pressed minute and current span.
  int? _pressed;
  ({int start, int end})? _drag;

  /// Hours of the current layout; empty night hours are folded.
  TimelineScale scale = TimelineScale.forBlocks(
    const [],
    hourHeight: AgendaDayPage.hourHeight,
  );

  @override
  void initState() {
    super.initState();
    data = widget.peekDays(widget.day, 1)?.firstOrNull;
    unawaited(_load());
  }

  @override
  void dispose() {
    scroll?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final next = (await widget.loadDays(widget.day, 1)).firstOrNull;
      if (mounted) setState(() => data = next);
    } catch (_) {
      // Not logged: may carry event details. The stale view stays.
    }
  }

  Future<void> _open(AgendaEntry entry) async {
    try {
      await widget.onOpen(entry);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Impossibile aprire l\'evento.')),
        );
      }
    }
    await _load();
  }

  Future<void> _createAt(double dy) async {
    final minutes = scale.minuteAt(dy);
    final slot = (minutes ~/ 30 * 30).clamp(0, 23 * 60 + 30);
    await widget.onCreate!(
      DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        slot ~/ 60,
        slot % 60,
      ),
    );
    await _load();
  }

  Future<void> _createDragged() async {
    final span = _drag;
    setState(() {
      _pressed = null;
      _drag = null;
    });
    if (span == null) return;
    DateTime at(int minute) => DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
      minute ~/ 60,
      minute % 60,
    );
    await widget.onCreate!(at(span.start), end: at(span.end));
    await _load();
  }

  /// Start a little before the first meeting, or around now for today.
  double _initialOffset(List<TimelineBlock> blocks) {
    final minute = blocks.isNotEmpty
        ? blocks.first.startMinute - 30
        : widget.day == widget.today
        ? widget.now().hour * 60 - 60
        : 8 * 60;
    return scale.y(minute.clamp(0, 24 * 60));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data?.entries ?? const <AgendaEntry>[];
    final allDay = [
      for (final entry in entries)
        if (entry.allDay) entry,
    ];
    final items = calendarVisitItems(entries, widget.day);
    final groups = {
      for (final item in items)
        if (item.grouped) item.first.instanceId: item,
    };
    final blocks = layoutDayTimeline(
      items.map((item) => item.timelineEntry).toList(),
      widget.day,
    );
    scale = TimelineScale.forBlocks(
      blocks,
      hourHeight: AgendaDayPage.hourHeight,
    );
    final clashing = agendaOverlaps(entries).keys.toSet();
    // The first layout fixes the initial position; reloads keep the scroll.
    scroll ??= data == null
        ? null
        : ScrollController(initialScrollOffset: _initialOffset(blocks));
    if (scroll == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(_gutter, 6, 8, 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in allDay)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: entry.isTask
                        ? Icon(
                            entry.completed
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                            size: 18,
                          )
                        : null,
                    backgroundColor: agendaEventFill(
                      widget.colors[entry.calendarIds.first] ??
                          theme.colorScheme.primaryContainer,
                      theme.colorScheme,
                    ),
                    label: Text(
                      entry.title.isEmpty ? '(senza titolo)' : entry.title,
                      style: TextStyle(
                        decoration: entry.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: agendaOnFill(
                          agendaEventFill(
                            widget.colors[entry.calendarIds.first] ??
                                theme.colorScheme.primaryContainer,
                            theme.colorScheme,
                          ),
                        ),
                      ),
                    ),
                    onPressed: () => unawaited(_open(entry)),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              // Edge-to-edge: keep 23:00–24:00 above the navigation bar.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
              ),
              child: SizedBox(
                height: scale.total,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      // Tapping free time creates an event there, rounded
                      // down to the half hour, like Google Calendar.
                      if (widget.onCreate != null)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const ValueKey('agenda-day-free-time'),
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) =>
                                unawaited(_createAt(details.localPosition.dy)),
                            // Hold and drag: the event's length (build 221).
                            onLongPressStart: (details) => setState(() {
                              _pressed = scale.minuteAt(
                                details.localPosition.dy,
                              );
                              _drag = dragSpan(_pressed!, _pressed! + 60);
                            }),
                            onLongPressMoveUpdate: (details) => setState(() {
                              _drag = dragSpan(
                                _pressed!,
                                scale.minuteAt(details.localPosition.dy),
                              );
                            }),
                            onLongPressEnd: (_) => unawaited(_createDragged()),
                            onLongPressCancel: () => setState(() {
                              _pressed = null;
                              _drag = null;
                            }),
                          ),
                        ),
                      for (var hour = 0; hour < 24; hour++)
                        ..._hourRow(context, hour, constraints.maxWidth),
                      for (final block in blocks)
                        _positioned(
                          context,
                          block,
                          constraints.maxWidth,
                          clashing,
                          groups[block.entry.instanceId],
                        ),
                      if (widget.day == widget.today)
                        _nowLine(context, constraints.maxWidth),
                      if (_drag case final span?)
                        Positioned(
                          key: const ValueKey('agenda-day-drag'),
                          top: scale.y(span.start),
                          height: scale.y(span.end) - scale.y(span.start),
                          left: _gutter,
                          right: 4,
                          child: AgendaDragGhost(span: span),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _hourRow(BuildContext context, int hour, double width) {
    final theme = Theme.of(context);
    final top = scale.y(hour * 60);
    final folded = scale.isFolded(hour);
    return [
      // Folded hours: a faint band, labelled only where it starts.
      if (folded)
        Positioned(
          top: top,
          left: _gutter,
          right: 0,
          height: scale.hourHeights[hour],
          child: IgnorePointer(
            child: ColoredBox(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
            ),
          ),
        ),
      Positioned(
        top: top,
        left: _gutter,
        right: 0,
        child: Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      if (hour > 0 && (!folded || !scale.isFolded(hour - 1)))
        Positioned(
          top: top - 7,
          left: 0,
          width: _gutter - 6,
          child: Text(
            '${hour.toString().padLeft(2, '0')}:00',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }

  Widget _positioned(
    BuildContext context,
    TimelineBlock block,
    double width,
    Set<String> clashing,
    CalendarVisitItem? group,
  ) {
    final slot = timelineSlot(block, width - _gutter - 4);
    final scheme = Theme.of(context).colorScheme;
    final color = agendaEventFill(
      widget.colors[block.entry.calendarIds.first] ?? scheme.primary,
      scheme,
    );
    return Positioned(
      key: ValueKey('agenda-block-${block.entry.instanceId}'),
      top: scale.y(block.startMinute) + 1,
      left: _gutter + slot.left,
      width: slot.width - 2,
      height: scale.y(block.endMinute) - scale.y(block.startMinute) - 2,
      child: group != null
          ? CalendarVisitGroup(item: group, color: color, onOpen: _open)
          : _Block(
              entry: block.entry,
              color: color,
              onTap: _open,
              onLongPress: widget.onLongPress == null
                  ? null
                  : (entry) async {
                      await widget.onLongPress!(entry);
                      await _load();
                    },
              clash: clashing.contains(block.entry.instanceId),
            ),
    );
  }

  Widget _nowLine(BuildContext context, double width) {
    final now = widget.now();
    final top = scale.y(now.hour * 60 + now.minute);
    final color = Theme.of(context).colorScheme.error;
    return Positioned(
      top: top - 4,
      left: _gutter - 4,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 2, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.entry,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.clash = false,
  });

  final Future<void> Function(AgendaEntry entry)? onLongPress;

  /// Overlaps another timed event: outlined and marked with ⚠.
  final bool clash;
  final AgendaEntry entry;
  final Color color;
  final Future<void> Function(AgendaEntry entry) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Unanswered invitations: outlined, not filled, like Google Calendar.
    final outlined = entry.unanswered;
    final onColor = outlined ? scheme.onSurface : agendaOnFill(color);
    final format = DateFormat.Hm('it');
    final meeting = entry.meeting;
    return Material(
      color: outlined ? scheme.surface : color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: clash
            ? BorderSide(color: scheme.error, width: 2)
            : outlined
            ? BorderSide(color: color, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(onTap(entry)),
        onLongPress: onLongPress == null
            ? null
            : () => unawaited(onLongPress!(entry)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tall = constraints.maxHeight >= 40;
            final roomy = constraints.maxHeight >= 56;
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? '(senza titolo)' : entry.title,
                    // Heights budgeted so title, time and link never overflow.
                    maxLines: constraints.maxHeight >= 80 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (tall)
                    Text(
                      '${clash ? '⚠ ' : ''}'
                      '${format.format(entry.start)}–${format.format(entry.end)}'
                      '${roomy && (entry.location?.trim().isNotEmpty ?? false) ? ' · ${entry.location!.trim()}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onColor, fontSize: 11),
                    ),
                  if (roomy && meeting != null) ...[
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: InkWell(
                        onTap: () => unawaited(
                          launchUrl(
                            meeting.url,
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Text(
                            'Partecipa · ${meeting.provider}',
                            style: TextStyle(
                              color: onColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: onColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The span being dragged out for a new event, with its times.
class AgendaDragGhost extends StatelessWidget {
  const AgendaDragGhost({required this.span, super.key});

  final ({int start, int end}) span;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String time(int minute) =>
        '${minute ~/ 60}:${(minute % 60).toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.25),
          border: Border.all(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 4, 0),
          child: Text(
            '${time(span.start)}–${time(span.end)}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
