import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';

/// Top of Today: up to three appointments on separate, aligned rows.
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
    final clock = DateFormat.Hm('it');
    final shown = upcoming.take(3).toList();
    final more = upcoming.length - shown.length;
    // "ora" for what is under way, "tra N min" for the first one still to
    // start within the hour.
    final labels = <String, String>{};
    for (final entry in shown) {
      final label = relativeStartLabel(entry.start, entry.end, now);
      if (label == null) continue;
      if (label != 'ora' && labels.values.any((l) => l != 'ora')) continue;
      labels[entry.instanceId] = label;
    }
    _scheduleTick(labels.isNotEmpty);
    final summary = [
      if (more > 0) '+$more altri',
      if (allDay > 0) '$allDay tutto il giorno',
    ].join(' · ');
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        key: const ValueKey('today-agenda-strip'),
        onTap: widget.onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, entry) in shown.indexed) ...[
                        if (index > 0) const SizedBox(height: 6),
                        Row(
                          key: ValueKey(
                            'today-agenda-event-${entry.instanceId}',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: MediaQuery.textScalerOf(context).scale(42),
                              child: Text(
                                clock.format(entry.start),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (widget.colorOf != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  key: ValueKey(
                                    'today-agenda-dot-${entry.instanceId}',
                                  ),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color:
                                        widget.colorOf!(entry) ??
                                        theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (labels[entry.instanceId]
                                        case final label?)
                                      TextSpan(
                                        text: '$label · ',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    TextSpan(
                                      text: entry.title.isEmpty
                                          ? '(senza titolo)'
                                          : entry.title,
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (summary.isNotEmpty) ...[
                        if (shown.isNotEmpty) const SizedBox(height: 8),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (shown.isEmpty && summary.isEmpty)
                        Text(
                          'Nessun altro impegno oggi',
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
