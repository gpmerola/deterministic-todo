import 'package:flutter/material.dart';

import '../../domain/task.dart';
import '../../services/agenda_service.dart';

/// One compact row: view mode, today, recognised zone, calendars and the
/// shell's search/settings (the app bar is hidden in Agenda to give the days
/// more room).
class AgendaHeader extends StatelessWidget {
  const AgendaHeader({
    required this.visible,
    required this.total,
    required this.loading,
    required this.mode,
    this.filtered = false,
    required this.onMode,
    required this.onToday,
    required this.today,
    required this.onChoose,
    this.zone,
    this.onSearch,
    this.onSettings,
    this.onCapture,
    this.onCreate,
    this.onPinCalendar,
    this.failures = 0,
    this.onFailures,
    this.onBackup,
    this.backupPending = false,
    this.onReminders,
    super.key,
  });

  /// Supabase backup of Todo's own Agenda data (phone only).
  final VoidCallback? onBackup;
  final VoidCallback? onReminders;

  /// The account holds a backup this phone has not restored yet.
  final bool backupPending;

  /// Web changes the phone could not apply.
  final int failures;
  final VoidCallback? onFailures;
  final VoidCallback? onCapture;
  final VoidCallback? onCreate;
  final VoidCallback? onPinCalendar;
  final String? zone;
  final int visible;
  final int total;
  final bool loading;
  final AgendaViewMode mode;
  final bool filtered;
  final ValueChanged<AgendaViewMode> onMode;
  final VoidCallback? onToday;

  /// Shown inside the Today button, as calendar apps do.
  final CivilDate today;
  final VoidCallback onChoose;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;

  static const _modes = {
    // One distinct shape per view (three looked alike, build 219).
    AgendaViewMode.threeDays: (Icons.view_column_outlined, '3 giorni', '3 gg'),
    AgendaViewMode.week: (Icons.calendar_view_week, 'Settimana', 'Sett.'),
    AgendaViewMode.twoWeeks: (
      Icons.date_range_outlined,
      '2 settimane',
      '2 sett.',
    ),
    AgendaViewMode.threeWeeks: (
      Icons.calendar_view_month,
      '3 settimane',
      '3 sett.',
    ),
    AgendaViewMode.fourWeeks: (
      Icons.calendar_view_month,
      '4 settimane',
      '4 sett.',
    ),
    AgendaViewMode.month: (Icons.calendar_view_month, 'Mese', 'Mese'),
    AgendaViewMode.list: (Icons.view_agenda_outlined, 'Elenco', 'Elenco'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          PopupMenuButton<AgendaViewMode>(
            key: const ValueKey('agenda-mode'),
            tooltip: 'Vista: ${_modes[mode]!.$2}',
            initialValue: mode,
            onSelected: onMode,
            // Word plus arrow: the bare grid icon did not say it opens views.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_modes[mode]!.$1, size: 20),
                  const SizedBox(width: 4),
                  Text(_modes[mode]!.$3, style: theme.textTheme.labelLarge),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
            itemBuilder: (_) => [
              for (final entry in _modes.entries)
                if (entry.key.offered || entry.key == mode)
                  PopupMenuItem(
                    key: ValueKey('agenda-mode-${entry.key.name}'),
                    value: entry.key,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(entry.value.$1),
                      title: Text(entry.value.$2),
                    ),
                  ),
            ],
          ),
          if (onToday != null)
            IconButton(
              key: const ValueKey('agenda-today'),
              tooltip: 'Oggi',
              onPressed: onToday,
              icon: AgendaTodayIcon(day: today.day),
            ),
          if (onCreate != null)
            IconButton(
              key: const ValueKey('agenda-new-event'),
              tooltip: 'Nuovo evento',
              visualDensity: VisualDensity.compact,
              onPressed: onCreate,
              icon: Icon(Icons.add, color: theme.colorScheme.primary),
            ),
          // The list has no period title: the zone stays here. Grids show
          // it beside their title (see AgendaView).
          Expanded(
            child: zone == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: loading
                        ? const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const SizedBox.shrink(),
                  )
                : AgendaZoneLabel(text: zone!, loading: loading),
          ),
          if (failures > 0)
            IconButton(
              key: const ValueKey('agenda-failures'),
              tooltip: 'Modifiche non applicate dal telefono',
              visualDensity: VisualDensity.compact,
              onPressed: onFailures,
              icon: Badge.count(
                count: failures,
                child: Icon(Icons.sync_problem, color: theme.colorScheme.error),
              ),
            ),
          if (backupPending && onBackup != null)
            IconButton(
              key: const ValueKey('agenda-backup-pending'),
              tooltip: 'Backup del Calendario da ripristinare',
              visualDensity: VisualDensity.compact,
              onPressed: onBackup,
              icon: Badge(
                child: Icon(
                  Icons.cloud_download_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          TextButton.icon(
            key: const ValueKey('agenda-choose-calendars'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              // Accent only when filters hide something; a plain count is
              // not an alert.
              foregroundColor: filtered ? theme.colorScheme.primary : muted,
            ),
            onPressed: total == 0 ? null : onChoose,
            icon: Icon(filtered ? Icons.filter_alt : Icons.tune, size: 18),
            label: Text(
              total == 0 ? '0' : '$visible/$total',
              semanticsLabel: 'Calendari: $visible di $total',
            ),
          ),
          // The assistant lives here since build 299, to keep the row short.
          if (onCapture != null ||
              onSearch != null ||
              onSettings != null ||
              onBackup != null ||
              onReminders != null ||
              onPinCalendar != null)
            PopupMenuButton<String>(
              key: const ValueKey('agenda-more'),
              tooltip: 'Altro',
              onSelected: (value) {
                if (value == 'capture') onCapture?.call();
                if (value == 'search') onSearch?.call();
                if (value == 'settings') onSettings?.call();
                if (value == 'backup') onBackup?.call();
                if (value == 'reminders') onReminders?.call();
                if (value == 'pinCalendar') onPinCalendar?.call();
              },
              itemBuilder: (_) => [
                if (onCapture != null)
                  const PopupMenuItem(
                    key: ValueKey('agenda-ai-capture'),
                    value: 'capture',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_awesome),
                      title: Text('Assistente: scrivi o detta'),
                    ),
                  ),
                if (onReminders != null)
                  const PopupMenuItem(
                    value: 'reminders',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.notifications_outlined),
                      title: Text('Promemoria'),
                    ),
                  ),
                if (onPinCalendar != null)
                  const PopupMenuItem(
                    value: 'pinCalendar',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_to_home_screen),
                      title: Text('Aggiungi alla schermata Home'),
                    ),
                  ),
                if (onSearch != null)
                  const PopupMenuItem(
                    value: 'search',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.search_rounded),
                      title: Text('Cerca'),
                    ),
                  ),
                if (onBackup != null)
                  const PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_outlined),
                      title: Text('Backup del Calendario'),
                    ),
                  ),
                if (onSettings != null)
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.settings_outlined),
                      title: Text('Impostazioni'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Recognised zone (and on the web the copy's age), always visible: every
/// time shown is in it.
class AgendaZoneLabel extends StatelessWidget {
  const AgendaZoneLabel({required this.text, required this.loading, super.key});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public, size: 13, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            key: const ValueKey('agenda-zone'),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ),
        if (loading) ...[
          const SizedBox(width: 6),
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ],
      ],
    );
  }
}

/// Calendar outline with today's day number.
class AgendaTodayIcon extends StatelessWidget {
  const AgendaTodayIcon({required this.day, super.key});

  final int day;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return SizedBox.square(
      dimension: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.calendar_today_outlined),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
