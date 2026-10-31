import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';

/// Top of Today: up to two appointments on compact one-line rows; what
/// does not fit becomes "+N" and an all-day count on the right (build 315).
/// Reads on build, on resume and on new day. Near appointments show
/// a countdown, refreshed by a one-shot timer, never in background.
/// The whole strip opens the day view; meeting links live in the calendar.
class TodayAgendaStrip extends StatefulWidget {
  const TodayAgendaStrip({
    required this.loadEntries,
    required this.onOpen,
    required this.dayKey,
    this.now,
    this.colorOf,
    super.key,
  });

  /// Calendar colour of an entry, drawn as a dot before it (build 224).
  final Color? Function(AgendaEntry entry)? colorOf;

  /// Today's Agenda entries (calendar events; tasks are filtered out here).
  final Future<List<AgendaEntry>> Function() loadEntries;
  final VoidCallback onOpen;

  /// Changes at midnight so the strip reloads.
  final String dayKey;
  final DateTime Function()? now;

  /// Timed appointments shown as rows; the rest is counted as "+N".
  static const maxRows = 2;

  @override
  State<TodayAgendaStrip> createState() => _TodayAgendaStripState();
}

class _TodayAgendaStripState extends State<TodayAgendaStrip>
    with WidgetsBindingObserver {
  List<AgendaEntry>? entries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TodayAgendaStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayKey != widget.dayKey) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    } else {
      // Nothing ticks in background.
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final next = await widget.loadEntries();
      if (mounted) setState(() => entries = next);
    } catch (_) {
      // Not logged: entries carry event titles. The strip stays hidden.
    }
  }

  Timer? _tick;

  /// Re-renders at the next minute while a countdown is shown.
  void _scheduleTick(bool counting) {
    _tick?.cancel();
    _tick = null;
    if (!counting) return;
    final now = (widget.now ?? DateTime.now)();
    _tick = Timer(Duration(seconds: 60 - now.second, milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = entries;
    if (all == null) return const SizedBox.shrink();
    final now = (widget.now ?? DateTime.now)();
    final events = [
      for (final entry in all)
        if (!entry.isTask) entry,
    ];
    final allDay = events.where((e) => e.allDay).length;
    final upcoming = [
      for (final entry in events)
        if (!entry.allDay && entry.end.isAfter(now)) entry,
    ];
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final clock = DateFormat.Hm('it');
    final shown = upcoming.take(TodayAgendaStrip.maxRows).toList();
    final more = upcoming.length - shown.length;
    // "ora" for what is under way, "tra N min" for the first one still to
    // start within the hour, abbreviated to "tra Nm" (build 315).
    final labels = <String, String>{};
    for (final entry in shown) {
      final label = relativeStartLabel(entry.start, entry.end, now);
      if (label == null) continue;
      if (label != 'ora' && labels.values.any((l) => l != 'ora')) continue;
      labels[entry.instanceId] = compactRelativeLabel(label);
    }
    _scheduleTick(labels.isNotEmpty);
    final rowStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.25);
    final Widget body;
    if (shown.isEmpty) {
      // One line of text: the rows are absent, so the full words fit.
      body = Text(
        allDay > 0
            ? '$allDay tutto il giorno · nessun altro impegno'
            : 'Nessun altro impegno oggi',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: rowStyle?.copyWith(color: muted),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, entry) in shown.indexed) ...[
            if (index > 0) const SizedBox(height: 2),
            Row(
              key: ValueKey('today-agenda-event-${entry.instanceId}'),
              children: [
                if (widget.colorOf != null) ...[
                  Container(
                    key: ValueKey('today-agenda-dot-${entry.instanceId}'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          widget.colorOf!(entry) ?? theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(40),
                  child: Text(
                    clock.format(entry.start),
                    // Never wraps: a second line would double the row.
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: rowStyle?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (labels[entry.instanceId] case final label?)
                          TextSpan(
                            text: '$label · ',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        TextSpan(
                          text: entry.title.isEmpty
                              ? '(senza titolo)'
                              : entry.title,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rowStyle,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }
    // What does not fit in the rows, compact on the right: "+2" more
    // appointments, a small calendar icon with the all-day count.
    final trailingStyle = theme.textTheme.labelMedium?.copyWith(color: muted);
    final trailing = [
      if (more > 0)
        Text(
          '+$more',
          key: const ValueKey('today-agenda-more'),
          semanticsLabel: '$more altri impegni',
          style: trailingStyle,
        ),
      if (allDay > 0 && shown.isNotEmpty)
        Semantics(
          key: const ValueKey('today-agenda-allday'),
          label: '$allDay tutto il giorno',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_outlined, size: 14, color: muted),
              const SizedBox(width: 2),
              Text('$allDay', style: trailingStyle),
            ],
          ),
        ),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        key: const ValueKey('today-agenda-strip'),
        onTap: widget.onOpen,
        child: ConstrainedBox(
          // Still a comfortable tap target with a single row.
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Expanded(child: body),
                for (final item in trailing) ...[
                  const SizedBox(width: 8),
                  item,
                ],
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 18, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "tra 25 min" → "tra 25m", "tra 1 ora" → "tra 1h"; "ora" unchanged.
String compactRelativeLabel(String label) => label
    .replaceFirst(RegExp(r' min$'), 'm')
    .replaceFirst(RegExp(r' ora$'), 'h');
