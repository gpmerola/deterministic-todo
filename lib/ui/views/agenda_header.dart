import 'package:flutter/material.dart';

import '../../services/agenda_service.dart';

/// One compact row: view mode, new event, notices and the Altro menu with
/// calendars, assistant, search and settings (the app bar is hidden in
/// Agenda to give the days more room). The Today icon and the "16/32"
/// calendar count were removed as clutter (build 306).
class AgendaHeader extends StatelessWidget {
  const AgendaHeader({
    required this.loading,
    required this.mode,
    this.filtered = false,
    required this.onMode,
    required this.onChoose,
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
  final bool loading;
  final AgendaViewMode mode;
  final bool filtered;
  final ValueChanged<AgendaViewMode> onMode;

  /// Calendars and filters; null while no calendar is known.
  final VoidCallback? onChoose;
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
    AgendaViewMode.fourWeeks: (
      Icons.calendar_view_month,
      '4 settimane',
      '4 sett.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          if (onCreate != null)
            IconButton(
              key: const ValueKey('agenda-new-event'),
              tooltip: 'Nuovo evento',
              visualDensity: VisualDensity.compact,
              onPressed: onCreate,
              icon: Icon(Icons.add, color: theme.colorScheme.primary),
            ),
          // The zone sits beside the grid's period title (see AgendaView).
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: loading
                  ? const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const SizedBox.shrink(),
            ),
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
          // The assistant (build 299) and the calendars (build 306) live
          // here, to keep the row short.
          if (onChoose != null ||
              onCapture != null ||
              onSearch != null ||
              onSettings != null ||
              onBackup != null ||
              onReminders != null ||
              onPinCalendar != null)
            PopupMenuButton<String>(
              key: const ValueKey('agenda-more'),
              tooltip: 'Altro',
              onSelected: (value) {
                if (value == 'calendars') onChoose?.call();
                if (value == 'capture') onCapture?.call();
                if (value == 'search') onSearch?.call();
                if (value == 'settings') onSettings?.call();
                if (value == 'backup') onBackup?.call();
                if (value == 'reminders') onReminders?.call();
                if (value == 'pinCalendar') onPinCalendar?.call();
              },
              itemBuilder: (_) => [
                if (onChoose != null)
                  PopupMenuItem(
                    key: const ValueKey('agenda-choose-calendars'),
                    value: 'calendars',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        filtered ? Icons.filter_alt : Icons.tune,
                        color: filtered ? theme.colorScheme.primary : null,
                      ),
                      title: const Text('Calendari e filtri'),
                    ),
                  ),
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
