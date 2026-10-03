import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart';
import '../../services/agenda_service.dart';
import 'agenda_day_view.dart';
import 'agenda_event_editor.dart';
import 'agenda_event_sheet.dart';
import 'agenda_month_view.dart';
import 'agenda_weeks_view.dart';

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
  AgendaFilter filter = AgendaFilter.none;
  List<AgendaDay> days = const [];
  int dayCount = AgendaView.pageDays;
  AgendaViewMode mode = AgendaViewMode.twoWeeks;

  /// Recognised device zone, always shown; null only if Android cannot tell.
  String? zone;

  /// Bumped on every successful reload so month grids drop cached events.
  int revision = 0;
  final monthScroll = ScrollController();
  final weeksPage = PageController(initialPage: AgendaWeeksView.pagesBack);
  bool loading = true;
  bool failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedFromMemory();
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
    monthScroll.dispose();
    weeksPage.dispose();
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
      final nextZone = await widget.service.deviceZoneLabel();
      final nextMode = await widget.service.viewMode();
      final nextFilter = await widget.service.filter();
      final nextCalendars = await widget.service.calendars();
      final nextHidden = hiddenAgendaCalendars(
        nextCalendars,
        await widget.service.calendarChoices(),
      );
      // The month view reads each month itself; only the list needs a window.
      final nextDays = nextMode == AgendaViewMode.list
          ? await _readDays(
              nextCalendars,
              nextHidden,
              nextFilter,
              widget.today,
              dayCount,
            )
          : days;
      if (!mounted || generation != _generation) return;
      setState(() {
        access = nextAccess;
        mode = nextMode;
        zone = nextZone;
        calendars = nextCalendars;
        hidden = nextHidden;
        filter = nextFilter;
        days = nextDays;
        revision++;
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

  /// Paints the last session results at once; [_load] then revalidates.
  void _seedFromMemory() {
    final service = widget.service;
    final cachedCalendars = service.lastCalendars;
    final cachedChoices = service.lastChoices;
    if (cachedCalendars == null || cachedChoices == null) return;
    access = AgendaAccess.granted;
    calendars = cachedCalendars;
    hidden = hiddenAgendaCalendars(cachedCalendars, cachedChoices);
    filter = service.lastFilter ?? AgendaFilter.none;
    mode = service.lastMode ?? AgendaViewMode.twoWeeks;
    zone = service.lastZoneLabel;
    days = _peekDays(widget.today, dayCount) ?? const [];
  }

  List<AgendaDay>? _peekDays(CivilDate first, int count) {
    final events = widget.service
        .cachedEvents(first.asLocalDate, first.addDays(count).asLocalDate, [
          for (final calendar in calendars)
            if (!hidden.contains(calendar.id)) calendar.id,
        ]);
    if (events == null) return null;
    return buildAgenda(
      events: events,
      calendars: calendars,
      hiddenCalendarIds: hidden,
      filter: filter,
      first: first,
      days: count,
    );
  }

  Future<List<AgendaDay>> _readDays(
    List<AgendaCalendar> calendars,
    Set<String> hidden,
    AgendaFilter filter,
    CivilDate first,
    int count,
  ) async {
    final events = await widget.service
        .events(first.asLocalDate, first.addDays(count).asLocalDate, [
          for (final calendar in calendars)
            if (!hidden.contains(calendar.id)) calendar.id,
        ]);
    return buildAgenda(
      events: events,
      calendars: calendars,
      hiddenCalendarIds: hidden,
      filter: filter,
      first: first,
      days: count,
    );
  }

  /// Opens the form and writes the event into the chosen phone calendar.
  Future<void> _createEvent({DateTime? start}) async {
    final writable = [
      for (final calendar in calendars)
        if (calendar.writable) calendar,
    ];
    final initialCalendar = defaultEventCalendar(
      calendars,
      await widget.service.lastEventCalendar(),
      hidden: hidden,
    );
    if (!mounted) return;
    final now = DateTime.now();
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          calendars: writable,
          initialStart:
              start ?? DateTime(now.year, now.month, now.day, now.hour + 1),
          initialCalendarId: initialCalendar,
          zoneLabel: zone,
        ),
      ),
    );
    if (draft == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final target = calendars.where((c) => c.id == draft.calendarId).firstOrNull;
    try {
      await widget.service.createEvent(draft);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            hidden.contains(draft.calendarId)
                ? 'Evento salvato in ${target?.name ?? 'calendario'}, '
                      'nascosto nell\'Agenda.'
                : 'Evento salvato in ${target?.name ?? 'calendario'}.',
          ),
        ),
      );
    } catch (_) {
      // Not logged: the draft carries the user's text.
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossibile salvare l\'evento.')),
      );
    }
    await _load();
  }

  Future<void> _setMode(AgendaViewMode next) async {
    if (next == mode) return;
    await widget.service.saveViewMode(next);
    await _load();
  }

  void _scrollToToday() {
    if (mode == AgendaViewMode.twoWeeks && weeksPage.hasClients) {
      unawaited(
        weeksPage.animateToPage(
          AgendaWeeksView.pagesBack,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (monthScroll.hasClients) {
      unawaited(
        monthScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
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
    final selection = await showModalBottomSheet<AgendaPickerResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AgendaCalendarPicker(
        calendars: calendars,
        hidden: hidden,
        filter: filter,
      ),
    );
    if (selection == null) return;
    await widget.service.saveCalendarChoices({
      for (final calendar in calendars)
        calendar.id: !selection.hidden.contains(calendar.id),
    });
    await widget.service.saveFilter(selection.filter);
    await _load();
  }

  AgendaCalendar? _calendarOf(AgendaEntry entry) =>
      calendars.where((c) => c.id == entry.calendarIds.first).firstOrNull;

  /// Editable here only in a writable calendar and when the user organises
  /// it: changing someone else's invitation would be overwritten by its sync.
  bool _editable(AgendaEntry entry) =>
      (_calendarOf(entry)?.writable ?? false) && entry.isOrganizer;

  /// Detail sheet of an occurrence, then the chosen action.
  Future<void> _showEvent(AgendaEntry entry) async {
    final calendar = _calendarOf(entry);
    final action = await showAgendaEventSheet(
      context,
      entry: entry,
      calendarName: calendar == null
          ? ''
          : calendar.accountName.isEmpty ||
                calendar.accountName == calendar.name
          ? calendar.name
          : '${calendar.name} · ${calendar.accountName}',
      editable: _editable(entry),
      zoneLabel: zone,
      color: _parseColor(calendar?.colorHex),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case AgendaEventAction.edit:
        await _editEvent(entry);
      case AgendaEventAction.delete:
        await _deleteEvent(entry);
      case AgendaEventAction.openInCalendar:
        try {
          await widget.service.openEvent(entry.instanceId);
        } catch (_) {
          _say('Impossibile aprire l\'evento.');
        }
    }
    await _load();
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editEvent(AgendaEntry entry) async {
    final series = entry.recurring
        ? await askSeriesScope(context, delete: false)
        : false;
    if (series == null || !mounted) return;
    final AgendaEventDraft? existing;
    try {
      existing = await widget.service.draftFor(entry.instanceId);
    } catch (_) {
      _say('Impossibile leggere l\'evento.');
      return;
    }
    if (existing == null || !mounted) {
      _say('L\'evento non esiste più.');
      return;
    }
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          calendars: [?_calendarOf(entry)],
          initialStart: existing!.start,
          existing: existing,
          zoneLabel: zone,
        ),
      ),
    );
    if (draft == null) return;
    try {
      await widget.service.updateEvent(entry.instanceId, draft, series: series);
      _say(series ? 'Serie aggiornata.' : 'Evento aggiornato.');
    } catch (_) {
      // Not logged: the draft carries the user's text.
      _say('Impossibile aggiornare l\'evento.');
    }
  }

  Future<void> _deleteEvent(AgendaEntry entry) async {
    final bool? series;
    if (entry.recurring) {
      series = await askSeriesScope(context, delete: true);
    } else {
      series = await confirmDelete(context, entry.title) ? false : null;
    }
    if (series == null) return;
    try {
      await widget.service.deleteEvent(entry.instanceId, series: series);
      _say(series ? 'Serie eliminata.' : 'Evento eliminato.');
    } catch (_) {
      _say('Impossibile eliminare l\'evento.');
    }
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
    final header = _AgendaHeader(
      visible: calendars.length - hidden.length,
      total: calendars.length,
      loading: loading,
      mode: mode,
      filtered: filter.isActive,
      onMode: (next) => unawaited(_setMode(next)),
      onToday: mode == AgendaViewMode.list ? null : _scrollToToday,
      zone: zone,
      onChoose: _chooseCalendars,
    );
    void openDay(CivilDate day) => unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AgendaDayPage(
            initialDay: day,
            today: widget.today,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            colors: colors,
            onOpen: _showEvent,
            onCreate: (start) => _createEvent(start: start),
            zoneLabel: zone,
          ),
        ),
      ),
    );
    final body = mode == AgendaViewMode.twoWeeks
        ? AgendaWeeksView(
            today: widget.today,
            revision: revision,
            controller: weeksPage,
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
          )
        : mode == AgendaViewMode.month
        ? AgendaMonthView(
            today: widget.today,
            revision: revision,
            controller: monthScroll,
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
          )
        : ListView.builder(
            key: const PageStorageKey('agenda-list'),
            padding: const EdgeInsets.only(bottom: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: days.length + 1,
            itemBuilder: (context, index) {
              if (index == days.length) {
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
              return _AgendaDaySection(
                day: days[index],
                today: widget.today,
                colors: colors,
                names: names,
                onOpen: (entry) => unawaited(_showEvent(entry)),
              );
            },
          );
    return Stack(
      children: [
        Column(
          children: [
            header,
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: body),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            key: const ValueKey('agenda-new-event'),
            heroTag: 'agenda-new-event',
            tooltip: 'Nuovo evento',
            onPressed: () => unawaited(_createEvent()),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.visible,
    required this.total,
    required this.loading,
    required this.mode,
    this.filtered = false,
    required this.onMode,
    required this.onToday,
    required this.onChoose,
    this.zone,
  });

  final String? zone;
  final int visible;
  final int total;
  final bool loading;
  final AgendaViewMode mode;
  final bool filtered;
  final ValueChanged<AgendaViewMode> onMode;
  final VoidCallback? onToday;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _row(context),
      // The recognised zone is always visible: every time shown is in it.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
        child: Row(
          children: [
            Icon(
              Icons.public,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                zone ?? 'Fuso orario non riconosciuto',
                key: const ValueKey('agenda-zone'),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _row(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
    child: Row(
      children: [
        SegmentedButton<AgendaViewMode>(
          key: const ValueKey('agenda-mode'),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(
              value: AgendaViewMode.twoWeeks,
              icon: Icon(Icons.view_week_outlined, size: 18),
              tooltip: '2 settimane',
            ),
            ButtonSegment(
              value: AgendaViewMode.month,
              icon: Icon(Icons.calendar_view_month, size: 18),
              tooltip: 'Mese',
            ),
            ButtonSegment(
              value: AgendaViewMode.list,
              icon: Icon(Icons.view_agenda_outlined, size: 18),
              tooltip: 'Elenco',
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) => onMode(value.single),
        ),
        if (onToday != null)
          TextButton(
            key: const ValueKey('agenda-today'),
            onPressed: onToday,
            child: const Text('Oggi'),
          ),
        if (loading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('agenda-choose-calendars'),
              onPressed: total == 0 ? null : onChoose,
              icon: Icon(filtered ? Icons.filter_alt : Icons.tune, size: 18),
              // Only the count: with three view modes a word was cut off.
              label: Text(
                total == 0 ? '0' : '$visible/$total',
                semanticsLabel: 'Calendari: $visible di $total',
              ),
            ),
          ),
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

final class AgendaPickerResult {
  const AgendaPickerResult(this.hidden, this.filter);
  final Set<String> hidden;
  final AgendaFilter filter;
}

class AgendaCalendarPicker extends StatefulWidget {
  const AgendaCalendarPicker({
    required this.calendars,
    required this.hidden,
    this.filter = AgendaFilter.none,
    super.key,
  });

  final List<AgendaCalendar> calendars;
  final Set<String> hidden;
  final AgendaFilter filter;

  @override
  State<AgendaCalendarPicker> createState() => _AgendaCalendarPickerState();
}

class _AgendaCalendarPickerState extends State<AgendaCalendarPicker> {
  late final Set<String> hidden = {...widget.hidden};
  late bool hideUnanswered = widget.filter.hideUnanswered;
  late final List<String> words = [...widget.filter.hiddenWords];
  final wordInput = TextEditingController();

  @override
  void dispose() {
    wordInput.dispose();
    super.dispose();
  }

  void _addWord() {
    final word = wordInput.text.trim();
    if (word.isEmpty) return;
    setState(() {
      if (!words.any((w) => w.toLowerCase() == word.toLowerCase())) {
        words.add(word);
      }
      wordInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('Filtri', style: theme.textTheme.labelLarge),
      ),
      SwitchListTile(
        key: const ValueKey('agenda-hide-unanswered'),
        value: hideUnanswered,
        title: const Text('Nascondi inviti senza risposta'),
        subtitle: const Text(
          'Riunioni a cui non hai accettato né rifiutato, come i broadcast',
        ),
        onChanged: (value) => setState(() => hideUnanswered = value),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('agenda-hidden-word'),
                controller: wordInput,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addWord(),
                decoration: const InputDecoration(
                  labelText: 'Nascondi eventi che contengono…',
                  hintText: 'es. Live Broadcast',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aggiungi parola',
              onPressed: _addWord,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      if (words.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in words)
                InputChip(
                  label: Text(word),
                  onDeleted: () => setState(() => words.remove(word)),
                ),
            ],
          ),
        ),
      const Divider(height: 24),
    ];
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
                  onPressed: () {
                    // A word typed but not yet added still counts.
                    _addWord();
                    Navigator.pop(
                      context,
                      AgendaPickerResult(
                        hidden,
                        AgendaFilter(
                          hideUnanswered: hideUnanswered,
                          hiddenWords: List.unmodifiable(words),
                        ),
                      ),
                    );
                  },
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
