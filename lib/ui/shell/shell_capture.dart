part of '../../main.dart';

/// ✨ capture, event-linked tasks and the universal search command.
extension _ShellCapture on _TaskShellState {
  Future<void> _openAiCapture() async {
    final settings = AiSettings();
    final config = await settings.read();
    if (!mounted) return;
    if (!config.hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configura prima la chiave in Impostazioni → Assistente AI.',
          ),
        ),
      );
      return;
    }
    // Calendar colours for the proposal cards, even before Agenda opened.
    if (agendaService.lastCalendars == null &&
        await agendaService.access() == AgendaAccess.granted) {
      await agendaService.calendars();
    }
    if (!mounted) return;
    final created = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AiCapturePage(
          client: AiClient(settings),
          providerLabel: config.provider.label,
          loadContext: aiActions.context,
          create: aiActions.create,
          calendarColors: {
            for (final calendar
                in agendaService.lastCalendars ?? const <AgendaCalendar>[])
              calendar.id: parseCalendarColor(calendar.colorHex),
          },
        ),
      ),
    );
    if (created == null || created == 0 || !mounted) return;
    unawaited(agendaSync?.changed());
    if (isAndroidPlatform) {
      unawaited(AgendaReminders(agendaService).foreground());
    }
    final batch = aiActions.lastCreated;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          created == 1 ? 'Creato 1 elemento ✨' : 'Creati $created elementi ✨',
        ),
        action: SnackBarAction(
          label: 'Annulla',
          onPressed: () => unawaited(_undoAiCreation(batch)),
        ),
      ),
    );
  }

  /// Removes one ✨ batch: tasks go to the trash (recoverable), events are
  /// deleted from their calendar.
  Future<void> _undoAiCreation(AiCreatedBatch batch) async {
    final failed = await aiActions.undo(batch);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Creazione ✨ annullata. Le attività sono nel cestino.'
              : 'Annullato in parte: $failed eventi da togliere a mano.',
        ),
      ),
    );
  }

  /// Agenda flows built from what the service already knows, so search can
  /// open the same event detail as the Agenda.
  AgendaEventFlows _agendaFlows() {
    final calendars = agendaService.lastCalendars ?? const <AgendaCalendar>[];
    return AgendaEventFlows(
      service: agendaService,
      calendars: calendars,
      hidden: hiddenAgendaCalendars(
        calendars,
        agendaService.lastChoices ?? const {},
        hideHolidays:
            (agendaService.lastFilter ?? AgendaFilter.none).hideHolidays,
      ),
      zone: agendaService.lastZoneLabel,
      onOpenTask: _openTaskById,
      onCreateTask: _createLinkedTask,
    );
  }

  /// "Preparare" / "Follow-up" from an event: a dated task, also shown in
  /// the Agenda so it sits next to the meeting.
  Future<void> _createLinkedTask(
    String title,
    CivilDate date,
    String notes,
  ) async {
    final db = widget.repository.db;
    final id = await widget.repository.create(
      title,
      showDate: date.toString(),
      notes: notes,
    );
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await AgendaTaskLinks(db).setShown(task, true);
    unawaited(agendaSync?.changed());
    if (isAndroidPlatform) {
      unawaited(AgendaReminders(agendaService).foreground());
    }
  }

  Future<void> _showUniversalCommand() => showSearch<void>(
    context: context,
    delegate: TaskSearchDelegate(
      widget.repository,
      searchEvents: _agendaAvailable
          ? (text) async {
              try {
                final results = await agendaService.searchEvents(
                  text,
                  DateTime.now(),
                );
                // Zone for the detail sheet, as in the Agenda.
                await agendaService.deviceZoneLabel();
                return results;
              } catch (_) {
                return const [];
              }
            }
          : null,
      openEvent: (context, entry) => _agendaFlows().show(context, entry),
      tileBuilder: (task) => TaskTile(
        key: ValueKey('search-${task.id}'),
        task: task,
        repository: widget.repository,
      ),
      onNavigate: (destination) {
        _navigateTo(destination);
      },
      onCreate: (raw) async {
        final metadata = parseQuickAddMetadata(
          raw,
          defaultPriority: 1,
          projectsByName: const {},
        );
        final parsed = parsePlannedQuickTask(metadata.text);
        await widget.repository.create(
          parsed.title,
          showDate: parsed.showDate!.toString(),
          recurrence: parsed.recurrence,
          priority: metadata.priority,
        );
      },
    ),
  );
}
