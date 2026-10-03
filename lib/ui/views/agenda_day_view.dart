import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';

typedef AgendaDaysLoader =
    Future<List<AgendaDay>> Function(CivilDate first, int days);
typedef AgendaDaysPeek = List<AgendaDay>? Function(CivilDate first, int days);

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
    required this.onCreate,
    this.now,
    super.key,
  });

  /// New event starting at the given time; completes once it is saved.
  final Future<void> Function(DateTime start) onCreate;

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
      shown.year == widget.today.year ? 'EEEE d MMMM' : 'EEEE d MMMM yyyy',
      'it',
    ).format(shown.asLocalDate);
    return Scaffold(
      appBar: AppBar(
        title: Text(label[0].toUpperCase() + label.substring(1)),
        actions: [
          if (shown != widget.today)
            TextButton(
              key: const ValueKey('agenda-day-today'),
              onPressed: _goToToday,
              child: const Text('Oggi'),
            ),
        ],
      ),
      body: PageView.builder(
        controller: pages,
        onPageChanged: (index) => setState(() => shown = _dayAt(index)),
        itemBuilder: (context, index) => AgendaDayTimeline(
          key: ValueKey('agenda-timeline-${_dayAt(index)}-$_refresh'),
          day: _dayAt(index),
          today: widget.today,
          loadDays: widget.loadDays,
          peekDays: widget.peekDays,
          colors: widget.colors,
          onOpen: widget.onOpen,
          onCreate: widget.onCreate,
          now: widget.now ?? DateTime.now,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('agenda-day-new-event'),
        tooltip: 'Nuovo evento',
        onPressed: () {
          final now = (widget.now ?? DateTime.now)();
          final hour = shown == widget.today ? now.hour + 1 : 9;
          unawaited(
            widget
                .onCreate(
                  DateTime(shown.year, shown.month, shown.day, hour.clamp(0, 23)),
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
    super.key,
  });

  final Future<void> Function(DateTime start) onCreate;
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
    final minutes = (dy / AgendaDayPage.hourHeight * 60).floor();
    final slot = (minutes ~/ 30 * 30).clamp(0, 23 * 60 + 30);
    await widget.onCreate(
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

  /// Start a little before the first meeting, or around now for today.
  double _initialOffset(List<TimelineBlock> blocks) {
    final minute = blocks.isNotEmpty
        ? blocks.first.startMinute - 30
        : widget.day == widget.today
        ? widget.now().hour * 60 - 60
        : 8 * 60;
    return (minute.clamp(0, 24 * 60) / 60) * AgendaDayPage.hourHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data?.entries ?? const <AgendaEntry>[];
    final allDay = [
      for (final entry in entries)
        if (entry.allDay) entry,
    ];
    final blocks = layoutDayTimeline(entries, widget.day);
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
                    backgroundColor:
                        widget.colors[entry.calendarIds.first] ??
                        theme.colorScheme.primaryContainer,
                    label: Text(
                      entry.title.isEmpty ? '(senza titolo)' : entry.title,
                      style: TextStyle(
                        color: _onColor(
                          widget.colors[entry.calendarIds.first] ??
                              theme.colorScheme.primaryContainer,
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
                height: 24 * AgendaDayPage.hourHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      // Tapping free time creates an event there, rounded
                      // down to the half hour, like Google Calendar.
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('agenda-day-free-time'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) =>
                              unawaited(_createAt(details.localPosition.dy)),
                        ),
                      ),
                      for (var hour = 0; hour < 24; hour++)
                        ..._hourRow(context, hour, constraints.maxWidth),
                      for (final block in blocks)
                        _positioned(context, block, constraints.maxWidth),
                      if (widget.day == widget.today)
                        _nowLine(context, constraints.maxWidth),
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
    final top = hour * AgendaDayPage.hourHeight;
    return [
      Positioned(
        top: top,
        left: _gutter,
        right: 0,
        child: Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      if (hour > 0)
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

  Widget _positioned(BuildContext context, TimelineBlock block, double width) {
    const unit = AgendaDayPage.hourHeight / 60;
    final available = width - _gutter - 4;
    final columnWidth = available / block.columns;
    final color =
        widget.colors[block.entry.calendarIds.first] ??
        Theme.of(context).colorScheme.primary;
    return Positioned(
      key: ValueKey('agenda-block-${block.entry.instanceId}'),
      top: block.startMinute * unit + 1,
      left: _gutter + block.column * columnWidth,
      width: columnWidth - 2,
      height: (block.endMinute - block.startMinute) * unit - 2,
      child: _Block(entry: block.entry, color: color, onTap: _open),
    );
  }

  Widget _nowLine(BuildContext context, double width) {
    final now = widget.now();
    final top = (now.hour * 60 + now.minute) * AgendaDayPage.hourHeight / 60;
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
  const _Block({required this.entry, required this.color, required this.onTap});

  final AgendaEntry entry;
  final Color color;
  final Future<void> Function(AgendaEntry entry) onTap;

  @override
  Widget build(BuildContext context) {
    final onColor = _onColor(color);
    final format = DateFormat.Hm('it');
    final meeting = entry.meeting;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(onTap(entry)),
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

Color _onColor(Color color) =>
    color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
