import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_visit_groups.dart';
import '../../domain/task.dart';
import 'calendar_visit_group.dart';

class AgendaDaySection extends StatelessWidget {
  const AgendaDaySection({
    required this.day,
    required this.today,
    required this.colors,
    required this.names,
    required this.onOpen,
    required this.onQuick,
    this.filtered = false,
    super.key,
  });

  final bool filtered;
  final ValueChanged<AgendaEntry> onQuick;
  final AgendaDay day;
  final CivilDate today;
  final Map<String, Color?> colors;
  final Map<String, String> names;
  final ValueChanged<AgendaEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The date is the pinned header above (see AgendaDayHeaderDelegate).
        if (day.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              filtered
                  ? 'Nessun evento visibile · filtri attivi'
                  : 'Nessun impegno',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final item in calendarVisitItems(day.entries, day.date))
            if (item.grouped)
              CalendarVisitGroup(
                item: item,
                color:
                    colors[item.first.calendarIds.first] ??
                    theme.colorScheme.primary,
                onOpen: (entry) async => onOpen(entry),
              )
            else
              AgendaEntryTile(
                entry: item.first,
                day: day.date,
                color: colors[item.first.calendarIds.first],
                calendarNames: [
                  for (final id in item.first.calendarIds) names[id] ?? '',
                ],
                onTap: () => onOpen(item.first),
                onLongPress: () => onQuick(item.first),
              ),
        const Divider(height: 1),
      ],
    );
  }

  static String dayLabel(CivilDate date, CivilDate today) {
    final label = DateFormat('EEEE d MMMM', 'it').format(date.asLocalDate);
    final capitalised = label[0].toUpperCase() + label.substring(1);
    if (date == today) return 'Oggi · $capitalised';
    if (date == today.addDays(1)) return 'Domani · $capitalised';
    return capitalised;
  }
}

class AgendaEntryTile extends StatelessWidget {
  const AgendaEntryTile({
    required this.entry,
    required this.day,
    required this.color,
    required this.calendarNames,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final AgendaEntry entry;
  final CivilDate day;
  final Color? color;
  final List<String> calendarNames;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (entry.location != null && entry.location!.trim().isNotEmpty)
        entry.location!.trim(),
      agendaCalendarLabel(calendarNames),
    ].where((part) => part.isNotEmpty).join('\n');
    final meeting = entry.meeting;
    return InkWell(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: color ?? theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                agendaTimeLabel(entry, day),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.isTask ? (entry.completed ? '☑ ' : '☐ ') : ''}'
                    '${entry.title.isEmpty ? '(senza titolo)' : entry.title}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: entry.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (meeting != null)
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(meeting.url, mode: LaunchMode.externalApplication),
                ),
                child: Text(meeting.provider),
              ),
          ],
        ),
      ),
    );
  }
}

/// Source calendars without repeats: two accounts often share a holiday
/// calendar with the same name.
String agendaCalendarLabel(List<String> names) =>
    names.where((name) => name.isNotEmpty).toSet().join(' · ');

/// "Tutto il giorno", "09:00–10:30", or the part inside [day] for events
/// crossing midnight ("dalle 22:00", "fino 02:00").
String agendaTimeLabel(AgendaEntry entry, CivilDate day) {
  if (entry.allDay) return 'Tutto il giorno';
  final format = DateFormat.Hm('it');
  final dayStart = day.asLocalDate;
  final dayEnd = day.addDays(1).asLocalDate;
  final startsToday = !entry.start.isBefore(dayStart);
  final endsToday = !entry.end.isAfter(dayEnd);
  if (startsToday && endsToday) {
    return entry.end.isAfter(entry.start)
        ? '${format.format(entry.start)}–${format.format(entry.end)}'
        : format.format(entry.start);
  }
  if (startsToday) return 'dalle ${format.format(entry.start)}';
  if (endsToday) return 'fino ${format.format(entry.end)}';
  return 'Tutto il giorno';
}

/// Pinned date of one day in the list.
class AgendaDayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const AgendaDayHeaderDelegate({
    required this.label,
    required this.background,
    required this.style,
  });

  final String label;
  final Color background;
  final TextStyle? style;

  static const _height = 38.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(
    child: ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant AgendaDayHeaderDelegate old) =>
      old.label != label || old.background != background || old.style != style;
}
