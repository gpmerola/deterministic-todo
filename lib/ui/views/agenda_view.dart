import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/agenda_request.dart';
import '../../domain/task.dart';
import '../../services/agenda_backup.dart';
import '../../services/agenda_reminders.dart';
import '../../services/agenda_service.dart';
import '../../services/platform_runtime_native.dart'
    if (dart.library.js_interop) '../../services/platform_runtime_web.dart';
import '../../services/semble_service.dart';
import 'agenda_backup_sheet.dart';
import 'agenda_calendar_picker.dart';
import 'agenda_colors.dart';
import 'agenda_day_view.dart';
import 'agenda_event_flows.dart';
import 'agenda_header.dart';
import 'agenda_list_widgets.dart';
import 'agenda_load_controller.dart';
import 'agenda_month_view.dart';
import 'agenda_reminder_sheet.dart';
import 'agenda_week_view.dart';
import 'agenda_weeks_view.dart';

export 'agenda_calendar_picker.dart'
    show AgendaCalendarPicker, AgendaPickerResult;
export 'agenda_header.dart' show AgendaTodayIcon;
export 'agenda_list_widgets.dart'
    show AgendaEntryTile, agendaCalendarLabel, agendaTimeLabel;

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
  late final loader = AgendaLoadController(widget.service);
  bool _wasBackground = false;
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
    unawaited(_load(changed: false));
  }

  @override
  void didUpdateWidget(covariant AgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.today != widget.today) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wasBackground = true;
    }
    if (state == AppLifecycleState.resumed && _wasBackground) {
      _wasBackground = false;
      unawaited(_load(changed: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AgendaBackup.pending.removeListener(_backupChanged);
    loader.dispose();
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

  Future<void> _load({bool changed = true}) async {
    if (!mounted) return;
    final generation = ++_generation;
    if (changed) widget.service.invalidateEventCache();
    setState(() {
      loading = true;
    });
    try {
      final result = await loader.load(listFirst, dayCount, changed: changed);
      if (!mounted || generation != _generation) return;
      setState(() {
        access = result.access;
        if (result.access == AgendaAccess.granted) {
          mode = result.mode!;
          zone = result.zone;
          calendars = result.calendars!;
          hidden = result.hidden!;
          filter = result.filter!;
          days = result.days ?? days;
        }
        failed = false;
        revision = result.revision;
        loading = false;
      });
      if (isAndroidPlatform) {
        unawaited(
          AgendaReminders(widget.service).foreground(requestPermission: true),
        );
        // Semble layer (build 285): read after the events, never awaited.
        if (result.access == AgendaAccess.granted) {
          unawaited(
            SembleLayer.shared.refresh(
              today: widget.today,
              zoneLabel: zone,
              force: changed,
            ),
          );
        }
      }
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (request.retryable)
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await widget.service.retryRequest(
                                          request.id,
                                        );
                                      } catch (_) {
                                        // Stays listed; can be tried again.
                                      }
                                      setDialogState(() {});
                                    },
                                    child: const Text('Riprova'),
                                  ),
                                TextButton(
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
                              ],
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
  ) => loader.readDays(calendars, hidden, filter, first, count);

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
    final header = AgendaHeader(
      onReminders: isAndroidPlatform
          ? () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => AgendaReminderSheet(
                reminders: AgendaReminders(widget.service),
              ),
            )
          : null,
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
                      delegate: AgendaDayHeaderDelegate(
                        label: AgendaDaySection.dayLabel(
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
                      child: AgendaDaySection(
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
                    child: AgendaZoneLabel(text: zoneText, loading: loading),
                  ),
                ),
            ],
          ),
        ),
      ],
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
