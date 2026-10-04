import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';

/// Top of Today: the day's remaining appointments in one line, so tasks and
/// meetings are seen together. Reads on build, on resume and on new day;
/// no timer. Tapping opens the day view.
class TodayAgendaStrip extends StatefulWidget {
  const TodayAgendaStrip({
    required this.loadEntries,
    required this.onOpen,
    required this.dayKey,
    this.now,
    super.key,
  });

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
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
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
    final parts = [
      for (final entry in shown)
        '${clock.format(entry.start)} '
            '${entry.title.isEmpty ? '(senza titolo)' : entry.title}',
      if (more > 0) '+$more',
      if (allDay > 0) '$allDay tutto il giorno',
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        key: const ValueKey('today-agenda-strip'),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  parts.isEmpty
                      ? 'Nessun altro impegno oggi'
                      : parts.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
