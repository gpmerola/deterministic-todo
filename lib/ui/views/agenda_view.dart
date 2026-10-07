import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/agenda.dart';
import '../../domain/agenda_request.dart';
import '../../domain/calendar_visit_groups.dart';
import '../../domain/task.dart';
import '../../services/agenda_backup.dart';
import '../../services/agenda_service.dart';
import 'agenda_backup_sheet.dart';
import 'agenda_colors.dart';
import 'agenda_day_view.dart';
import 'agenda_event_flows.dart';
import 'agenda_month_view.dart';
import 'agenda_week_view.dart';
import 'agenda_weeks_view.dart';
import 'calendar_visit_group.dart';

/// Read-only agenda that merges every calendar the phone already syncs
/// (Google, Outlook/Exchange work accounts…). Android only.
class AgendaView extends StatefulWidget {
  const AgendaView({
    required this.service,
    required this.today,
    this.onOpenTask,
    this.onCreateTask,
    this.onSearch,
    this.onSettings,
    this.onCapture,
    this.onChanged,
    this.onPinCalendar,
    super.key,
  });

  /// After a change made here (event, calendars, filters): the shell
  /// refreshes the web mirror.
  final VoidCallback? onChanged;
  final Future<void> Function()? onPinCalendar;

  /// Opens the ✨ assistant; the Agenda reloads afterwards.
  final Future<void> Function()? onCapture;

  final AgendaService service;

  /// The shell's search and settings, offered here because the app bar is
  /// hidden in Agenda.
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;

  /// Opens a Todo task shown in the Agenda; the shell owns the task editor.
  final Future<void> Function(String taskId)? onOpenTask;

  /// Creates a linked Todo task from an event (Preparare / Follow-up).
  final Future<void> Function(String title, CivilDate date, String notes)?
  onCreateTask;
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
  late CivilDate selectedDay = widget.today;
  late CivilDate listFirst = widget.today;
  final _listViewport = GlobalKey();
  final Map<CivilDate, GlobalKey> _listDates = {};
  bool get hasFilters =>
      hidden.isNotEmpty ||
      filter.isActive ||
      filter.hideHolidays ||
      filter.hiddenEvents.isNotEmpty;
  void _periodChanged(CivilDate first, int count) {
    final last = first.addDays(count);
    if (selectedDay.asLocalDate.isBefore(first.asLocalDate) ||
        !selectedDay.asLocalDate.isBefore(last.asLocalDate)) {
      selectedDay = first;
    }
  }

  void _listScrolled() {
    if (mode != AgendaViewMode.list) return;
    final viewport = _listViewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    for (final day in days) {
      final box = _listDates[day.date]?.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.localToGlobal(Offset(0, box.size.height)).dy > top + 32) {
        selectedDay = day.date;
        return;
      }
    }
  }

  AgendaViewMode mode = AgendaViewMode.fourWeeks;

  /// Recognised device zone, always shown; null only if Android cannot tell.
  String? zone;

  /// Bumped on every successful reload so month grids drop cached events.
  int revision = 0;
  var monthPage = PageController(
    initialPage: AgendaMonthView.monthsBack,
    keepPage: false,
  );
  var weeksPage = PageController(
    initialPage: AgendaWeeksView.pagesBack,
    keepPage: false,
  );
  var weekPage = PageController(
    initialPage: AgendaWeekView.weeksBack,
    keepPage: false,
  );
  final listScroll = ScrollController();
  var threeDaysPage = PageController(
    initialPage: AgendaWeekView.weeksBack,
    keepPage: false,
  );
  bool loading = true;
  bool failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AgendaBackup.pending.addListener(_backupChanged);
    listScroll.addListener(_listScrolled);
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
    AgendaBackup.pending.removeListener(_backupChanged);
    monthPage.dispose();
    weeksPage.dispose();
    weekPage.dispose();
    threeDaysPage.dispose();
    listScroll.dispose();
    super.dispose();
  }

  void _backupChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      loading = true;
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
      // Independent reads: run together so a resume waits for the slowest
      // one instead of their sum.
      final (nextZone, nextMode, nextFilter, nextCalendars, choices) = await (
        widget.service.deviceZoneLabel(),
        widget.service.viewMode(),
        widget.service.filter(),
        widget.service.calendars(),
        widget.service.calendarChoices(),
      ).wait;
      final nextHidden = hiddenAgendaCalendars(
        nextCalendars,
        choices,
        hideHolidays: nextFilter.hideHolidays,
      );
      // The month view reads each month itself; only the list needs a window.
      final nextDays = nextMode == AgendaViewMode.list
          ? await _readDays(
              nextCalendars,
              nextHidden,
              nextFilter,
              listFirst,
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
        failed = false;
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

  /// Web changes the phone refused, each with its reason; dismissing one
  /// only removes the notice.
  Future<void> _showFailures() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final failed = widget.service.failedRequests;
          return AlertDialog(
            title: const Text('Non applicate dal telefono'),
            content: SizedBox(
              width: 420,
              child: failed.isEmpty
                  ? const Text('Nessuna.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final request in failed)
                          ListTile(
                            key: ValueKey('agenda-failure-${request.id}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(agendaRequestLabel(request)),
                            subtitle: Text(request.error ?? 'Non applicata.'),
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await widget.service.dismissRequest(
                                    request.id,
                                  );
                                } catch (_) {
                                  // Stays listed; the next load retries.
                                }
                                setDialogState(() {});
                              },
                              child: const Text('Ignora'),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      ),
    );
    await _load();
  }

  /// Paints the last session results at once; [_load] then revalidates.
  void _seedFromMemory() {
    final service = widget.service;
    final cachedCalendars = service.lastCalendars;
    final cachedChoices = service.lastChoices;
    if (cachedCalendars == null || cachedChoices == null) return;
    access = AgendaAccess.granted;
    calendars = cachedCalendars;
    hidden = hiddenAgendaCalendars(
      cachedCalendars,
      cachedChoices,
      hideHolidays: (service.lastFilter ?? AgendaFilter.none).hideHolidays,
    );
    filter = service.lastFilter ?? AgendaFilter.none;
    mode = service.lastMode ?? AgendaViewMode.fourWeeks;
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
      tasks: widget.service.cachedTasks(first, count) ?? const [],
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
      tasks: await widget.service.tasks(first, count),
      calendars: calendars,
      hiddenCalendarIds: hidden,
      filter: filter,
      first: first,
      days: count,
    );
  }

  AgendaEventFlows get _flows => AgendaEventFlows(
    service: widget.service,
    calendars: calendars,
    hidden: hidden,
    zone: zone,
    onOpenTask: widget.onOpenTask,
    onCreateTask: widget.onCreateTask,
    onChanged: () {
      unawaited(_load());
      widget.onChanged?.call();
    },
  );

  Future<void> _createEvent({DateTime? start, DateTime? end}) async {
    await _flows.create(context, start: start, end: end);
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _showEvent(AgendaEntry entry) async {
    final changed = await _flows.show(context, entry);
    await _load();
    if (changed) widget.onChanged?.call();
  }

  Future<void> _quickEvent(AgendaEntry entry) async {
    final changed = await _flows.quickActions(context, entry);
    await _load();
    if (changed) widget.onChanged?.call();
  }

  Future<void> _setMode(AgendaViewMode next) async {
    if (next == mode) return;
    await widget.service.saveViewMode(next);
    if (!mounted) return;
    final today = widget.today;
    int daysBetween(CivilDate a, CivilDate b) => DateTime.utc(
      a.year,
      a.month,
      a.day,
    ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
    final delta = daysBetween(selectedDay, today);
    PageController replacement(int page, int max) =>
        PageController(initialPage: page.clamp(0, max - 1), keepPage: false);
    switch (next) {
      case AgendaViewMode.month:
        monthPage.dispose();
        monthPage = replacement(
          AgendaMonthView.monthsBack +
              (selectedDay.year - today.year) * 12 +
              selectedDay.month -
              today.month,
          AgendaMonthView.monthsBack + AgendaMonthView.monthsAhead,
        );
      case AgendaViewMode.week:
        weekPage.dispose();
        weekPage = replacement(
          AgendaWeekView.weeksBack +
              (daysBetween(selectedDay, mondayOf(today)) / 7).floor(),
          AgendaWeekView.weeksBack + AgendaWeekView.weeksAhead,
        );
      case AgendaViewMode.threeDays:
        threeDaysPage.dispose();
        threeDaysPage = replacement(
          AgendaWeekView.weeksBack + (delta / 3).floor(),
          AgendaWeekView.weeksBack + AgendaWeekView.weeksAhead,
        );
      case AgendaViewMode.twoWeeks:
      case AgendaViewMode.threeWeeks:
      case AgendaViewMode.fourWeeks:
        weeksPage.dispose();
        weeksPage = replacement(
          AgendaWeeksView.pagesBack +
              (daysBetween(selectedDay, mondayOf(today)) / (next.gridWeeks * 7))
                  .floor(),
          AgendaWeeksView.pagesBack + AgendaWeeksView.pagesAhead,
        );
      case AgendaViewMode.list:
        listFirst = selectedDay;
        dayCount = AgendaView.pageDays;
        _listDates.clear();
    }
    await _load();
  }

  void _scrollToToday() {
    selectedDay = widget.today;
    if (mode == AgendaViewMode.list && listFirst != widget.today) {
      listFirst = widget.today;
      unawaited(_load());
    }
    // The list starts today.
    if (mode == AgendaViewMode.list && listScroll.hasClients) {
      unawaited(
        listScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (mode == AgendaViewMode.threeDays && threeDaysPage.hasClients) {
      unawaited(
        threeDaysPage.animateToPage(
          AgendaWeekView.weeksBack,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (mode == AgendaViewMode.week && weekPage.hasClients) {
      unawaited(
        weekPage.animateToPage(
          AgendaWeekView.weeksBack,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if ((mode.gridWeeks > 0) && weeksPage.hasClients) {
      unawaited(
        weeksPage.animateToPage(
          AgendaWeeksView.pagesBack,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (mode == AgendaViewMode.month && monthPage.hasClients) {
      unawaited(
        monthPage.animateToPage(
          AgendaMonthView.monthsBack,
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
    final eventCalendar = defaultEventCalendar(
      calendars,
      await widget.service.lastEventCalendar(),
      hidden: hidden,
    );
    final aiCalendar = await widget.service.aiEventCalendar();
    final userColors = await widget.service.calendarColors();
    if (!mounted) return;
    final selection = await showModalBottomSheet<AgendaPickerResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AgendaCalendarPicker(
        calendars: calendars,
        hidden: hidden,
        filter: filter,
        eventCalendarId: eventCalendar,
        aiEventCalendarId: aiCalendar,
        colors: widget.service.canOpenInSystem ? userColors : null,
      ),
    );
    if (selection == null) return;
    if (selection.colors != null) {
      await widget.service.saveCalendarColors(selection.colors!);
    }
    await widget.service.saveAiEventCalendar(selection.aiEventCalendarId);
    if (selection.eventCalendarId != null) {
      await widget.service.saveEventCalendar(selection.eventCalendarId!);
    }
    await widget.service.saveCalendarChoices({
      for (final calendar in calendars)
        calendar.id: !selection.hidden.contains(calendar.id),
    });
    await widget.service.saveFilter(selection.filter);
    widget.onChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (access == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (failed && calendars.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        text: 'Impossibile leggere i calendari del telefono.',
        action: 'Riprova',
        onAction: _load,
      );
    }
    if (access == AgendaAccess.noMirror) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text:
            'Sul Web il Calendario mostra la copia inviata dal telefono. Apri Todo '
            'sul telefono con la sincronizzazione attiva: la copia arriva in '
            'pochi secondi.',
        action: 'Riprova',
        onAction: _load,
      );
    }
    if (access != AgendaAccess.granted) {
      return _Message(
        icon: Icons.calendar_month_outlined,
        text:
            'Il Calendario legge i calendari del telefono. Se attivi la sincronizzazione, '
            'una copia viene inviata al tuo account per consultarla sul Web.',
        action: access == AgendaAccess.denied
            ? 'Apri impostazioni'
            : 'Consenti accesso al calendario',
        onAction: _requestAccess,
      );
    }
    final colors = {
      for (final calendar in calendars)
        calendar.id: parseCalendarColor(calendar.colorHex),
    };
    final names = {
      for (final calendar in calendars) calendar.id: calendar.name,
    };
    final zoneText = [
      zone == null
          // Not yet known while the first load runs.
          ? (loading ? 'Fuso…' : 'Fuso non riconosciuto')
          : shortZoneLabel(zone!),
      ?widget.service.mirrorLabel,
    ].join(' · ');
    final backup = AgendaBackup.current;
    final header = _AgendaHeader(
      backupPending: AgendaBackup.pending.value != null,
      onBackup: backup == null
          ? null
          : () async {
              if (await showAgendaBackupSheet(context, backup)) {
                widget.onChanged?.call();
                await _load();
              }
            },
      visible: calendars.length - hidden.length,
      total: calendars.length,
      loading: loading,
      mode: mode,
      filtered: hasFilters,
      onMode: (next) => unawaited(_setMode(next)),
      onToday: _scrollToToday,
      onCreate: widget.service.canWrite
          ? () => unawaited(_createEvent())
          : null,
      today: widget.today,
      zone: mode == AgendaViewMode.list ? zoneText : null,
      onChoose: _chooseCalendars,
      failures: widget.service.failedRequests.length,
      onFailures: _showFailures,
      onPinCalendar: widget.onPinCalendar,
      onSearch: widget.onSearch,
      onSettings: widget.onSettings,
      onCapture: widget.onCapture == null
          ? null
          : () async {
              await widget.onCapture!();
              await _load();
            },
    );
    void openDay(CivilDate day) {
      selectedDay = day;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AgendaPalette(
              child: AgendaDayPage(
                initialDay: day,
                onDayChanged: (day) => selectedDay = day,
                today: widget.today,
                loadDays: (first, count) =>
                    _readDays(calendars, hidden, filter, first, count),
                peekDays: _peekDays,
                colors: colors,
                onOpen: _showEvent,
                onLongPress: _quickEvent,
                onCreate: widget.service.canWrite
                    ? (start, {end}) => _createEvent(start: start, end: end)
                    : null,
                zoneLabel: zone,
              ),
            ),
          ),
        ),
      );
    }

    final body = mode == AgendaViewMode.threeDays
        ? AgendaWeekView(
            key: const ValueKey('agenda-three-days'),
            dayCount: 3,
            today: widget.today,
            revision: revision,
            controller: threeDaysPage,
            onPeriodChanged: (day) => _periodChanged(day, 3),
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
            onOpen: _showEvent,
            onLongPress: _quickEvent,
            onCreate: widget.service.canWrite
                ? (start, {end}) => _createEvent(start: start, end: end)
                : null,
          )
        : mode == AgendaViewMode.week
        ? AgendaWeekView(
            today: widget.today,
            revision: revision,
            controller: weekPage,
            onPeriodChanged: (day) => _periodChanged(day, 7),
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
            onOpen: _showEvent,
            onLongPress: _quickEvent,
            onCreate: widget.service.canWrite
                ? (start, {end}) => _createEvent(start: start, end: end)
                : null,
          )
        : mode.gridWeeks > 0
        ? AgendaWeeksView(
            key: ValueKey(mode),
            weekCount: mode.gridWeeks,
            onOpenEntry: _showEvent,
            today: widget.today,
            revision: revision,
            controller: weeksPage,
            onPeriodChanged: (day) => _periodChanged(day, mode.gridWeeks * 7),
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
          )
        : mode == AgendaViewMode.month
        ? AgendaMonthView(
            onOpenEntry: _showEvent,
            today: widget.today,
            revision: revision,
            controller: monthPage,
            onPeriodChanged: (day) =>
                _periodChanged(day, DateTime(day.year, day.month + 1, 0).day),
            colors: colors,
            loadDays: (first, count) =>
                _readDays(calendars, hidden, filter, first, count),
            peekDays: _peekDays,
            onOpenDay: openDay,
          )
        // Each day's date stays pinned at the top while its events scroll
        // under it (build 224).
        : CustomScrollView(
            key: ValueKey('agenda-list:$listFirst'),
            controller: listScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final day in days)
                SliverMainAxisGroup(
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _DayHeaderDelegate(
                        label: _AgendaDaySection.dayLabel(
                          day.date,
                          widget.today,
                        ),
                        background: agendaDateHeaderFill(
                          Theme.of(context).colorScheme,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _AgendaDaySection(
                        key: _listDates.putIfAbsent(day.date, GlobalKey.new),
                        filtered: hasFilters,
                        day: day,
                        today: widget.today,
                        colors: colors,
                        names: names,
                        onOpen: (entry) => unawaited(_showEvent(entry)),
                        onQuick: (entry) => unawaited(_quickEvent(entry)),
                      ),
                    ),
                  ],
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: OutlinedButton(
                    key: const ValueKey('agenda-load-more'),
                    onPressed: () {
                      dayCount += AgendaView.pageDays;
                      unawaited(_load());
                    },
                    child: const Text('Mostra altri 14 giorni'),
                  ),
                ),
              ),
            ],
          );
    return Column(
      children: [
        header,
        if (failed)
          MaterialBanner(
            content: const Text(
              'Aggiornamento non riuscito. Mostro gli ultimi dati disponibili.',
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : _load,
                child: const Text('Riprova'),
              ),
            ],
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SizedBox(
                  key: _listViewport,
                  child: RefreshIndicator(onRefresh: _load, child: body),
                ),
              ),
              // Grids have a period title on the left of their first
              // row; the zone sits on its right, where there is room
              // (in the header it was cut to "Londo…", build 217).
              if (mode != AgendaViewMode.list)
                Positioned(
                  top: 1,
                  right: 12,
                  child: IgnorePointer(
                    child: _ZoneLabel(text: zoneText, loading: loading),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One compact row: view mode, today, recognised zone, calendars and the
/// shell's search/settings (the app bar is hidden in Agenda to give the days
/// more room).
class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
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
  });

  /// Supabase backup of Todo's own Agenda data (phone only).
  final VoidCallback? onBackup;

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
                : _ZoneLabel(text: zone!, loading: loading),
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
          if (onCapture != null)
            IconButton(
              key: const ValueKey('agenda-ai-capture'),
              tooltip: 'Assistente: scrivi o detta',
              visualDensity: VisualDensity.compact,
              onPressed: onCapture,
              icon: const Icon(Icons.auto_awesome),
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
          if (onSearch != null ||
              onSettings != null ||
              onBackup != null ||
              onPinCalendar != null)
            PopupMenuButton<String>(
              key: const ValueKey('agenda-more'),
              tooltip: 'Altro',
              onSelected: (value) {
                if (value == 'search') onSearch?.call();
                if (value == 'settings') onSettings?.call();
                if (value == 'backup') onBackup?.call();
                if (value == 'pinCalendar') onPinCalendar?.call();
              },
              itemBuilder: (_) => [
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

class _AgendaDaySection extends StatelessWidget {
  const _AgendaDaySection({
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
        // The date is the pinned header above (see _DayHeaderDelegate).
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

final class AgendaPickerResult {
  const AgendaPickerResult(
    this.hidden,
    this.filter, {
    this.eventCalendarId,
    this.aiEventCalendarId,
    this.colors,
  });

  /// User colours by calendar id; null when the picker did not offer them.
  final Map<String, String>? colors;

  /// Separate calendar for ✨ events; null means "same as new events".
  final String? aiEventCalendarId;
  final Set<String> hidden;
  final AgendaFilter filter;

  /// Calendar for new events (+ and ✨ assistant).
  final String? eventCalendarId;
}

class AgendaCalendarPicker extends StatefulWidget {
  const AgendaCalendarPicker({
    required this.calendars,
    required this.hidden,
    this.filter = AgendaFilter.none,
    this.eventCalendarId,
    this.aiEventCalendarId,
    this.colors,
    super.key,
  });

  /// Colours the user picked; null hides the colour choice.
  final Map<String, String>? colors;

  final String? aiEventCalendarId;
  final List<AgendaCalendar> calendars;
  final Set<String> hidden;
  final AgendaFilter filter;
  final String? eventCalendarId;

  @override
  State<AgendaCalendarPicker> createState() => _AgendaCalendarPickerState();
}

class _AgendaCalendarPickerState extends State<AgendaCalendarPicker> {
  late final Set<String> hidden = {...widget.hidden};
  late bool hideUnanswered = widget.filter.hideUnanswered;
  late bool hideHolidays = widget.filter.hideHolidays;
  late String? eventCalendarId = widget.eventCalendarId;
  late String? aiEventCalendarId = widget.aiEventCalendarId;
  late final List<String> words = [...widget.filter.hiddenWords];
  late final List<HiddenAgendaEvent> hiddenEvents = [
    ...widget.filter.hiddenEvents,
  ];
  late final Map<String, String>? colors = widget.colors == null
      ? null
      : {...widget.colors!};

  bool get hasFilters =>
      hidden.isNotEmpty ||
      hideHolidays ||
      hideUnanswered ||
      words.isNotEmpty ||
      hiddenEvents.isNotEmpty;

  String get filterSummary => [
    if (hidden.isNotEmpty) '${hidden.length} calendari nascosti',
    if (hideHolidays) 'festività nascoste',
    if (hideUnanswered) 'inviti senza risposta nascosti',
    if (words.isNotEmpty) '${words.length} filtri per parola',
    if (hiddenEvents.isNotEmpty) '${hiddenEvents.length} eventi/serie nascosti',
  ].join(' · ');

  void _clearFilters() => setState(() {
    hidden.clear();
    hideHolidays = false;
    hideUnanswered = false;
    words.clear();
    hiddenEvents.clear();
    wordInput.clear();
  });

  /// Google Calendar's event colours, with their Italian names.
  static const palette = [
    ('Pomodoro', '#D50000'),
    ('Fenicottero', '#E67C73'),
    ('Mandarino', '#F4511E'),
    ('Banana', '#F6BF26'),
    ('Salvia', '#33B679'),
    ('Basilico', '#0B8043'),
    ('Pavone', '#039BE5'),
    ('Mirtillo', '#3F51B5'),
    ('Lavanda', '#7986CB'),
    ('Uva', '#8E24AA'),
    ('Grafite', '#616161'),
  ];

  Future<void> _chooseColor(AgendaCalendar calendar) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Colore di ${calendar.name}'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (name, hex) in palette)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      key: ValueKey('agenda-color-$hex'),
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(dialogContext, hex),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: parseCalendarColor(hex),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SimpleDialogOption(
            key: const ValueKey('agenda-color-reset'),
            // Empty string: back to the calendar's own colour.
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Colore originale del calendario'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      picked.isEmpty
          ? colors!.remove(calendar.id)
          : colors![calendar.id] = picked;
    });
  }

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
    final writable = [
      for (final calendar in widget.calendars)
        if (calendar.writable) calendar,
    ];
    final rows = <Widget>[
      if (writable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('agenda-event-calendar-default'),
            initialValue: writable.any((c) => c.id == eventCalendarId)
                ? eventCalendarId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nuovi eventi in (+)'),
            items: [
              for (final calendar in writable)
                DropdownMenuItem(
                  value: calendar.id,
                  child: Text(
                    calendar.accountName.isEmpty ||
                            calendar.accountName == calendar.name
                        ? calendar.name
                        : '${calendar.name} · ${calendar.accountName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => eventCalendarId = value),
          ),
        ),
      if (writable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('agenda-ai-event-calendar'),
            initialValue: writable.any((c) => c.id == aiEventCalendarId)
                ? aiEventCalendarId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Eventi creati da ✨ in',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Come i nuovi eventi'),
              ),
              for (final calendar in writable)
                DropdownMenuItem<String?>(
                  value: calendar.id,
                  child: Text(
                    calendar.accountName.isEmpty ||
                            calendar.accountName == calendar.name
                        ? calendar.name
                        : '${calendar.name} · ${calendar.accountName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => aiEventCalendarId = value),
          ),
        ),
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
      SwitchListTile(
        key: const ValueKey('agenda-hide-holidays'),
        value: hideHolidays,
        title: const Text('Nascondi festività'),
        subtitle: const Text(
          'Calendari delle feste nazionali e religiose di ogni account',
        ),
        onChanged: (value) => setState(() => hideHolidays = value),
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
      if (hiddenEvents.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Nascosti in Todo (${hiddenEvents.length})',
            key: const ValueKey('agenda-hidden-events'),
            style: theme.textTheme.labelLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            'Restano nei loro calendari; qui non compaiono.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final hidden in hiddenEvents.reversed)
          ListTile(
            dense: true,
            title: Text(
              hidden.title.isEmpty ? '(senza titolo)' : hidden.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              hidden.series
                  ? 'Tutti gli eventi con questo titolo'
                  : DateFormat(
                      hidden.allDay ? 'EEE d MMM yyyy' : 'EEE d MMM yyyy HH:mm',
                      'it',
                    ).format(hidden.start),
            ),
            trailing: TextButton(
              key: ValueKey('agenda-show-${hidden.key}'),
              onPressed: () => setState(() => hiddenEvents.remove(hidden)),
              child: const Text('Ripristina'),
            ),
          ),
      ],
      const Divider(height: 24),
      if (colors != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            'Tocca il pallino per scegliere il colore di un calendario.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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
      final holiday = hideHolidays && isHolidayCalendar(calendar);
      rows.add(
        SwitchListTile(
          // Held off by "Nascondi festività" while that is on.
          value: !holiday && !hidden.contains(calendar.id),
          subtitle: holiday ? const Text('Festività: nascosto') : null,
          // Tap the dot to choose a colour (build 221).
          secondary: InkWell(
            key: ValueKey('agenda-color-of-${calendar.id}'),
            customBorder: const CircleBorder(),
            onTap: colors == null ? null : () => _chooseColor(calendar),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                radius: 8,
                backgroundColor:
                    parseCalendarColor(
                      colors?[calendar.id] ?? calendar.colorHex,
                    ) ??
                    theme.colorScheme.primary,
              ),
            ),
          ),
          title: Text(calendar.name),
          onChanged: holiday
              ? null
              : (show) => setState(() {
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
                'Calendari e filtri',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (hasFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(filterSummary, style: theme.textTheme.bodySmall),
              ),
            Flexible(child: ListView(shrinkWrap: true, children: rows)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: hasFilters ? _clearFilters : null,
                    child: const Text('Azzera filtri'),
                  ),
                  FilledButton(
                    onPressed: () {
                      // A word typed but not yet added still counts.
                      _addWord();
                      Navigator.pop(
                        context,
                        AgendaPickerResult(
                          colors: colors,
                          hidden,
                          AgendaFilter(
                            hideUnanswered: hideUnanswered,
                            hiddenWords: List.unmodifiable(words),
                            hideHolidays: hideHolidays,
                            hiddenEvents: List.unmodifiable(hiddenEvents),
                          ),
                          eventCalendarId: eventCalendarId,
                          aiEventCalendarId: aiEventCalendarId,
                        ),
                      );
                    },
                    child: const Text('Applica'),
                  ),
                ],
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

/// Recognised zone (and on the web the copy's age), always visible: every
/// time shown is in it.
class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({required this.text, required this.loading});

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

/// Pinned date of one day in the list.
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate({
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
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.label != label || old.background != background || old.style != style;
}
