import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/semble_bookings.dart' show SembleBookingEntry;
import '../../domain/task.dart';
import 'agenda_colors.dart';
import 'agenda_semble_layer.dart' show SemblePalette;

/// Pieces shared by the grids (2 and 4 weeks) and the week strip: the
/// weekday initials and one entry in a cell.
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

/// "9:00", "16:30": always hours and minutes. Until build 219 whole hours
/// were shortened to "9", which read as a number rather than a time; the
/// time now has its own line, so the minutes fit.
String compactTime(DateTime moment) =>
    '${moment.hour}:${moment.minute.toString().padLeft(2, '0')}';

/// One entry in a grid cell, Google Calendar style: all-day events are
/// filled with their calendar colour, timed events are a coloured dot and
/// the title (so the title gets the whole width), Todo tasks a checkbox.
class AgendaChip extends StatelessWidget {
  const AgendaChip({
    required this.entry,
    required this.color,
    this.showTime = false,
    this.twoLines = false,
    this.day,
    this.inSemble = false,
    super.key,
  });

  /// Not a visit, inside bookable Semble time: amber mark (build 300).
  final bool inSemble;

  /// The cell's day: a multi-day all-day event then joins its neighbours
  /// as one bar, titled once (on its first day and on Mondays).
  final CivilDate? day;

  /// Prefixes the start time of timed events (only where space allows).
  final bool showTime;

  /// Timed events as time over title (narrow grid cells).
  final bool twoLines;

  /// Height of a [twoLines] timed entry; other entries use
  /// `AgendaDayCell.chipHeight`.
  static const twoLineHeight = 25.0;

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
      final fill = agendaEventFill(color, theme.colorScheme);
      final cell = day;
      final before = cell != null && entry.start.isBefore(cell.asLocalDate);
      final after =
          cell != null && entry.end.isAfter(cell.addDays(1).asLocalDate);
      final titled = !before || cell.asLocalDate.weekday == DateTime.monday;
      const round = Radius.circular(3);
      return Container(
        // Continuing sides reach the cell edge and stay square.
        margin: EdgeInsets.only(
          bottom: 1.5,
          left: before ? 0 : 1,
          right: after ? 0 : 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.horizontal(
            left: before ? Radius.zero : round,
            right: after ? Radius.zero : round,
          ),
        ),
        child: text(titled ? title : ' ', agendaOnFill(fill)),
      );
    }
    if (twoLines) {
      // Month and two-week cells are ~50 dp wide: the time gets its own
      // line, in the calendar colour, so it is always readable and the
      // title keeps the whole width below it.
      return Container(
        padding: const EdgeInsets.only(bottom: 2, left: 1),
        decoration: inSemble
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: SemblePalette.overlap(theme.colorScheme),
                    width: 2,
                  ),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              compactTime(entry.start),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: agendaAccentText(color, theme.colorScheme),
              ),
            ),
            // Unanswered invitation: muted and italic, still readable.
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: style.copyWith(
                color: entry.unanswered
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
                fontStyle: entry.unanswered ? FontStyle.italic : null,
                // Cancelled in Semble: the slot is free again (build 303).
                decoration: entry.isSembleCancelled
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ],
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
