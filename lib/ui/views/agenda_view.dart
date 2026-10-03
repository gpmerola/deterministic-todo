import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import '../../services/agenda_service.dart';

/// Read-only agenda that merges every calendar the phone already syncs
/// (Google, Outlook/Exchange work accounts…). Android only.
class AgendaView extends StatefulWidget {
  const AgendaView({required this.service, required this.today, super.key});

  final AgendaService service;
  final CivilDate today;

  static const pageDays = 14;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> with WidgetsBindingObserver {
  AgendaAccess? access;
  List<AgendaCalendar> calendars = const [];
  Set<String> hidden = const {};
  List<AgendaDay> days = const [];
  int dayCount = AgendaView.pageDays;
  bool loading = true;
  bool failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Outlook may have synced while the app was in background.
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final nextAccess = await widget.service.access();
      if (nextAccess != AgendaAccess.granted) {
        if (!mounted || generation != _generation) return;
        setState(() {
          access = nextAccess;
          loading = false;
        });
        return;
      }
      final nextCalendars = await widget.service.calendars();
      final nextHidden = hiddenAgendaCalendars(
        nextCalendars,
        await widget.service.calendarChoices(),
      );
      final start = widget.today.asLocalDate;
      final end = widget.today.addDays(dayCount).asLocalDate;
      final events = await widget.service.events(start, end, [
        for (final calendar in nextCalendars)
          if (!nextHidden.contains(calendar.id)) calendar.id,
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        access = nextAccess;
        calendars = nextCalendars;
        hidden = nextHidden;
        days = buildAgenda(
          events: events,
          calendars: nextCalendars,
          hiddenCalendarIds: nextHidden,
          first: widget.today,
          days: dayCount,
        );
        loading = false;
      });
    } catch (_) {
      // Deliberately not logged: messages may carry event details.
      if (!mounted || generation != _generation) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  Future<void> _requestAccess() async {
    final result = access == AgendaAccess.denied
        ? null
        : await widget.service.requestAccess();
    if (result == null) await widget.service.openSystemSettings();
    await _load();
  }

  Future<void> _chooseCalendars() async {
    final selection = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          AgendaCalendarPicker(calendars: calendars, hidden: hidden),
    );
    if (selection == null) return;
    await widget.service.saveCalendarChoices({
      for (final calendar in calendars)
        calendar.id: !selection.contains(calendar.id),
    });
    await _load();
  }

  Future<void> _open(AgendaEntry entry) async {
    try {
      await widget.service.openEvent(entry.instanceId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire l\'evento.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (access == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (access != AgendaAccess.granted) {
      return _Message(
        icon: Icons.calendar_month_outlined,
        text:
            'L\'agenda mostra insieme i calendari già sincronizzati sul '
            'telefono, compresi gli account Outlook di lavoro. Gli eventi '
            'restano sul telefono e non vengono sincronizzati.',
        action: access == AgendaAccess.denied
            ? 'Apri impostazioni'
            : 'Consenti accesso al calendario',
        onAction: _requestAccess,
      );
    }
    if (failed) {
      return _Message(
        icon: Icons.error_outline,
        text: 'Impossibile leggere i calendari del telefono.',
        action: 'Riprova',
        onAction: _load,
      );
    }
    final colors = {
      for (final calendar in calendars)
        calendar.id: _parseColor(calendar.colorHex),
    };
    final names = {
      for (final calendar in calendars) calendar.id: calendar.name,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const PageStorageKey('agenda-list'),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: days.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AgendaHeader(
              visible: calendars.length - hidden.length,
              total: calendars.length,
              loading: loading,
              onChoose: _chooseCalendars,
            );
          }
          if (index == days.length + 1) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                key: const ValueKey('agenda-load-more'),
                onPressed: () {
                  dayCount += AgendaView.pageDays;
                  unawaited(_load());
                },
                child: const Text('Mostra altri 14 giorni'),
              ),
            );
          }
          final day = days[index - 1];
          return _AgendaDaySection(
            day: day,
            today: widget.today,
            colors: colors,
            names: names,
            onOpen: _open,
          );
        },
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.visible,
    required this.total,
    required this.loading,
    required this.onChoose,
  });

  final int visible;
  final int total;
  final bool loading;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            total == 0
                ? 'Nessun calendario sul telefono'
                : '$visible di $total calendari',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (loading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton.icon(
          key: const ValueKey('agenda-choose-calendars'),
          onPressed: total == 0 ? null : onChoose,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Calendari'),
        ),
      ],
    ),
  );
}

class _AgendaDaySection extends StatelessWidget {
  const _AgendaDaySection({
    required this.day,
    required this.today,
    required this.colors,
    required this.names,
    required this.onOpen,
  });

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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
          child: Text(
            _dayLabel(day.date, today),
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (day.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Nessun evento',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final entry in day.entries)
            AgendaEntryTile(
              entry: entry,
              day: day.date,
              color: colors[entry.calendarIds.first],
              calendarNames: [
                for (final id in entry.calendarIds) names[id] ?? '',
              ],
              onTap: () => onOpen(entry),
            ),
        const Divider(height: 1),
      ],
    );
  }

  static String _dayLabel(CivilDate date, CivilDate today) {
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
    super.key,
  });

  final AgendaEntry entry;
  final CivilDate day;
  final Color? color;
  final List<String> calendarNames;
  final VoidCallback onTap;

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
                    entry.title.isEmpty ? '(senza titolo)' : entry.title,
                    style: theme.textTheme.bodyLarge,
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

class AgendaCalendarPicker extends StatefulWidget {
  const AgendaCalendarPicker({
    required this.calendars,
    required this.hidden,
    super.key,
  });

  final List<AgendaCalendar> calendars;
  final Set<String> hidden;

  @override
  State<AgendaCalendarPicker> createState() => _AgendaCalendarPickerState();
}

class _AgendaCalendarPickerState extends State<AgendaCalendarPicker> {
  late final Set<String> hidden = {...widget.hidden};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    String? account;
    for (final calendar in widget.calendars) {
      if (calendar.accountName != account) {
        account = calendar.accountName;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              account.isEmpty ? 'Sul telefono' : account,
              style: theme.textTheme.labelLarge,
            ),
          ),
        );
      }
      rows.add(
        SwitchListTile(
          value: !hidden.contains(calendar.id),
          secondary: CircleAvatar(
            radius: 7,
            backgroundColor:
                _parseColor(calendar.colorHex) ?? theme.colorScheme.primary,
          ),
          title: Text(calendar.name),
          onChanged: (show) => setState(() {
            show ? hidden.remove(calendar.id) : hidden.add(calendar.id);
          }),
        ),
      );
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Calendari nell\'agenda',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(child: ListView(shrinkWrap: true, children: rows)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, hidden),
                  child: const Text('Applica'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String action;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  final digits = hex.replaceFirst('#', '');
  final value = int.tryParse(digits, radix: 16);
  if (value == null) return null;
  return switch (digits.length) {
    6 => Color(0xff000000 | value),
    8 => Color(value),
    _ => null,
  };
}
