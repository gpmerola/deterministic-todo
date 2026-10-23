part of '../../main.dart';

/// The selected view's content, task tiles and the desktop detail pane.
extension _ShellContent on _TaskShellState {
  /// [loaded] is false until SQLite answers: the web database can take
  /// seconds to open, and an early "Nessuna attività" looks like data loss.
  Widget _content(List<Task> all, {bool loaded = true}) {
    if (navigation.section == AppSection.settings) {
      return ListenableBuilder(
        listenable: steps,
        builder: (context, _) => SettingsView(
          repository: widget.repository,
          syncClient: widget.syncClient,
          syncService: widget.syncService,
          autoBackup: autoBackup,
          earnings: isAndroidPlatform
              ? PrivateEarningsService(agendaService, semble: SembleSettings())
              : null,
          checkForUpdates: _checkForUpdates,
          showCompleted: () => _navigateTo(AppSection.completed),
          dailyStepGoal: steps.goal,
          onDailyStepGoalChanged: steps.setGoal,
        ),
      );
    }
    if (navigation.section == AppSection.agenda) {
      return SafeArea(
        bottom: false,
        child: AgendaPalette(
          child: AgendaView(
            service: agendaService,
            launch: calendarLaunch,
            onPinCalendar: isAndroidPlatform ? _pinCalendarShortcut : null,
            today: dayClock.today,
            onOpenTask: _openTaskById,
            onCreateTask: _createLinkedTask,
            onSearch: _showUniversalCommand,
            onCapture: isAndroidPlatform ? _openAiCapture : null,
            onSettings: () => _navigateTo(AppSection.settings),
            onChanged: () {
              unawaited(agendaSync?.changed());
              if (isAndroidPlatform) {
                unawaited(AgendaReminders(agendaService).foreground());
              }
            },
          ),
        ),
      );
    }
    if (navigation.section == AppSection.projects) {
      return ProjectsView(
        repository: widget.repository,
        syncService: widget.syncService,
        tasks: all,
        selectedProjectId: navigation.selectedProjectId,
        onSelectProject: (id) =>
            _update(() => navigation.selectedProjectId = id),
        beforeLeavingProject: () async =>
            await _closeDesktopEditor() && mounted,
        onAddTask: (projectId, sectionId) =>
            _showQuickAddSheet(projectId: projectId, sectionId: sectionId),
        tileBuilder: (task) => TaskTile(
          key: ValueKey('project-${task.id}'),
          task: task,
          repository: widget.repository,
          highlightRemote: recentlySyncedTaskIds.contains(task.id),
        ),
      );
    }
    final today = dayClock.today;
    // Membership comes from SQL (`watchView`); here rows are only ordered.
    final visible = List<Task>.of(all)
      ..sort(
        (a, b) => navigation.section == AppSection.upcoming
            ? compareByDateThenPriority(a, b, today.toString())
            : compareByPriority(a, b, today.toString()),
      );
    if (navigation.section == AppSection.upcoming) {
      final start = navigation.selectedUpcomingDate == null
          ? today.addDays(1)
          : CivilDate.parse(navigation.selectedUpcomingDate!);
      return Column(
        children: [
          UpcomingDateJump(
            today: today,
            selected: navigation.selectedUpcomingDate == null ? null : start,
            onSelected: (date) => _update(() {
              navigation.selectUpcomingDate(date.toString());
            }),
          ),
          Expanded(
            child: UpcomingTaskList(
              listKey: PageStorageKey(
                'upcoming-${navigation.selectedUpcomingDate}-${navigation.upcomingVisit}',
              ),
              tasks: visible,
              today: today,
              start: start,
              days: navigation.upcomingDays,
              onLoadMore: () => _update(() => navigation.upcomingDays += 30),
              tileBuilder: (task) => TaskTile(
                key: ValueKey(task.id),
                task: task,
                repository: widget.repository,
                showDateMetadata: false,
                highlightRemote: recentlySyncedTaskIds.contains(task.id),
              ),
            ),
          ),
        ],
      );
    }
    final list = AnimatedSwitcher(
      key: ValueKey('task-state-motion-${navigation.section.name}'),
      duration: _microMotion,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: visible.isEmpty && !loaded
          ? SizedBox.shrink(key: ValueKey('loading-${navigation.section.name}'))
          : visible.isEmpty
          ? EmptyViewLabel(
              navigation.section == AppSection.completed
                  ? 'Nessuna attività completata'
                  : 'Nessuna attività',
              key: ValueKey('empty-${navigation.section.name}'),
            )
          : navigation.section == AppSection.today
          ? TodayTaskList(
              tasks: visible,
              today: today.toString(),
              tileBuilder: _taskTile,
            )
          : ListView.builder(
              key: PageStorageKey('task-list-${navigation.section.name}'),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: visible.length,
              itemBuilder: (context, index) => _taskTile(visible[index]),
            ),
    );
    if (navigation.section != AppSection.today || !_agendaAvailable) {
      return list;
    }
    // Today's remaining appointments above the tasks: one look for both.
    return Column(
      children: [
        TodayAgendaStrip(
          dayKey: today.toString(),
          loadEntries: () async =>
              (await agendaService.agendaDays(today, 1)).single.entries,
          onOpen: () => unawaited(_openAgendaDay(today)),
          colorOf: (entry) => parseCalendarColor(
            agendaService.lastCalendars
                ?.where((c) => c.id == entry.calendarIds.first)
                .firstOrNull
                ?.colorHex,
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  /// Day view of the Agenda opened from elsewhere (Today strip).
  Future<void> _openAgendaDay(CivilDate day) async {
    await agendaService.deviceZoneLabel();
    if (!mounted) return;
    final flows = _agendaFlows();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => AgendaDayPage(
          initialDay: day,
          today: dayClock.today,
          loadDays: agendaService.agendaDays,
          peekDays: (_, _) => null,
          colors: {
            for (final calendar in flows.calendars)
              calendar.id: parseCalendarColor(calendar.colorHex),
          },
          onOpen: (entry) => flows.show(pageContext, entry),
          onLongPress: (entry) => flows.quickActions(pageContext, entry),
          onCreate: (start, {end}) =>
              flows.create(pageContext, start: start, end: end),
          zoneLabel: agendaService.lastZoneLabel,
        ),
      ),
    );
    if (mounted) _update(() {});
  }

  Widget _taskTile(Task task) => TaskTile(
    key: ValueKey(task.id),
    task: task,
    repository: widget.repository,
    highlightRemote: recentlySyncedTaskIds.contains(task.id),
    dense: navigation.section == AppSection.completed,
    showDateMetadata:
        navigation.section != AppSection.today &&
        navigation.section != AppSection.upcoming,
    onSelected: MediaQuery.sizeOf(context).width >= 900
        ? () async {
            if (selectedDesktopTaskId == task.id) return;
            if (await _closeDesktopEditor() && mounted) {
              _update(() {
                desktopEditorKey = GlobalKey<_TaskEditorState>();
                selectedDesktopTaskId = task.id;
              });
            }
          }
        : null,
  );

  Future<bool> _closeDesktopEditor() async {
    if (!await (desktopEditorKey.currentState?.preserveDraft() ??
        Future.value(true))) {
      return false;
    }
    if (mounted) _update(() => selectedDesktopTaskId = null);
    return true;
  }

  Widget _desktopItemDetails(Task task) => Padding(
    key: ValueKey('desktop-detail-${task.id}'),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dettagli',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Chiudi dettagli',
              onPressed: _closeDesktopEditor,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Focus(
            key: ValueKey('desktop-inline-editor-${task.id}'),
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                unawaited(_closeDesktopEditor());
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TaskEditor(
              key: desktopEditorKey,
              task: task,
              repository: widget.repository,
              embedded: true,
              onSaved: (_) => _update(() => selectedDesktopTaskId = null),
              onDeleted: () => _update(() => selectedDesktopTaskId = null),
            ),
          ),
        ),
      ],
    ),
  );
}
