part of '../main.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    required this.task,
    required this.repository,
    this.embedded = false,
    this.onSaved,
    this.onDeleted,
    super.key,
  });

  final Task task;
  final TaskRepository repository;
  final bool embedded;
  final ValueChanged<Task>? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final LinkTextEditingController title =
      LinkTextEditingController.fromMarkdown(
        widget.task.title,
        highlightSmartDates: true,
      );
  late final LinkTextEditingController notes =
      LinkTextEditingController.fromMarkdown(widget.task.notes);
  late final TextEditingController showDate = TextEditingController(
    text: widget.task.showDate,
  );
  late String recurrence = widget.task.recurrence ?? 'none';
  late String? projectId = widget.task.projectId;
  late String? projectSectionId = widget.task.sectionId;
  late int priority = widget.task.priority;
  bool dateExplicitlyCleared = false;
  bool saving = false;
  bool allowClose = false;
  late Task baseline = widget.task;
  late final drafts = EditorDrafts(widget.repository.db);
  bool draftRestored = false;
  bool restoringDraft = false;
  Timer? draftTimer;
  Future<void> draftWork = Future.value();

  void _scheduleDraft() {
    draftTimer?.cancel();
    if (saving || restoringDraft || allowClose) return;
    draftTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(preserveDraft());
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleDraft();
  }

  void _onEditorTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    title.addListener(_onEditorTextChanged);
    notes.addListener(_onEditorTextChanged);
    showDate.addListener(_onEditorTextChanged);
    unawaited(_restoreDraft().catchError((Object _) {}));
  }

  Future<void> _restoreDraft() async {
    final draft = await drafts.read(widget.task.id);
    if (!mounted || draft == null || !_matchesTask(baseline)) return;
    restoringDraft = true;
    setState(() {
      baseline = Task.fromJson(
        Map<String, dynamic>.from(draft['baseline'] as Map),
      );
      title.replaceMarkdown(draft['title'] as String);
      notes.replaceMarkdown(draft['notes'] as String?);
      showDate.text = draft['date'] as String? ?? '';
      recurrence = draft['recurrence'] as String;
      priority = draft['priority'] as int;
      projectId = draft['projectId'] as String?;
      projectSectionId = draft['sectionId'] as String?;
      dateExplicitlyCleared = draft['dateCleared'] == true;
      draftRestored = true;
    });
    restoringDraft = false;
  }

  Future<bool> preserveDraft() async {
    draftTimer?.cancel();
    if (saving) return false;
    try {
      if (_matchesTask(baseline)) {
        await (draftWork = draftWork.then(
          (_) => drafts.remove(widget.task.id),
        ));
      } else {
        final value = <String, dynamic>{
          'schema': 1,
          'baseline': baseline.toJson(),
          'title': title.toMarkdown(),
          'notes': notes.toMarkdown(),
          'date': showDate.text,
          'recurrence': recurrence,
          'priority': priority,
          'projectId': projectId,
          'sectionId': projectSectionId,
          'dateCleared': dateExplicitlyCleared,
        };
        await (draftWork = draftWork.then(
          (_) => drafts.write(widget.task.id, value),
        ));
      }
      return true;
    } on Object {
      draftWork = Future.value();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile conservare la bozza. L’editor resta aperto.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _closeWithDraft() async {
    if (!await preserveDraft() || !mounted) return;
    setState(() => allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  bool _matchesTask(Task task) =>
      !dateExplicitlyCleared &&
      title.toMarkdown() == task.title &&
      notes.toMarkdown().trim() == (task.notes ?? '').trim() &&
      showDate.text == (task.showDate ?? '') &&
      recurrence == (task.recurrence ?? 'none') &&
      projectId == task.projectId &&
      projectSectionId == task.sectionId &&
      priority == task.priority;

  @override
  void didUpdateWidget(covariant TaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.updatedAt == widget.task.updatedAt ||
        !_matchesTask(oldWidget.task) ||
        saving) {
      return;
    }
    baseline = widget.task;
    title.replaceMarkdown(widget.task.title);
    notes.replaceMarkdown(widget.task.notes);
    showDate.text = widget.task.showDate ?? '';
    recurrence = widget.task.recurrence ?? 'none';
    projectId = widget.task.projectId;
    projectSectionId = widget.task.sectionId;
    priority = widget.task.priority;
  }

  @override
  void dispose() {
    draftTimer?.cancel();
    title.dispose();
    notes.dispose();
    showDate.dispose();
    super.dispose();
  }

  Future<Task> _save() async {
    final elapsed = Stopwatch()..start();
    final hasSmartSyntax = const QuickAddParser()
        .recognizedSyntax(title.text)
        .isNotEmpty;
    if (hasSmartSyntax) {
      final parsed = parsePlannedQuickTask(title.text);
      title.text = parsed.title;
      if (!dateExplicitlyCleared && parsed.showDate != null) {
        showDate.text = parsed.showDate.toString();
      }
      if (parsed.recurrence != null) recurrence = parsed.recurrence!;
    }
    final plannedDate = plannedEditorDate(showDate.text);
    final today = CivilDate.fromDateTime(DateTime.now());
    final derivedStatus = plannedDate == null
        ? TaskStatus.inbox
        : plannedDate.compareTo(today) <= 0
        ? TaskStatus.available
        : TaskStatus.scheduled;
    await widget.repository.updateDetails(
      baseline,
      title: title.toMarkdown(),
      status:
          baseline.status == TaskStatus.completed.name ||
              plannedDate?.toString() == baseline.showDate
          ? TaskStatus.values.byName(baseline.status)
          : derivedStatus,
      notes: notes.text.trim().isEmpty ? null : notes.toMarkdown().trim(),
      showDate: plannedDate?.toString(),
      recurrence: recurrence == 'none' ? null : recurrence,
      priority: priority,
      projectId: projectId,
      sectionId: projectSectionId,
      updateProject: true,
    );
    final refreshed = await (widget.repository.db.select(
      widget.repository.db.tasks,
    )..where((row) => row.id.equals(widget.task.id))).getSingle();
    elapsed.stop();
    unawaited(
      DiagnosticLogService.instance.event(
        'interaction_latency',
        fields: {
          'interaction': 'task_edit_save',
          'outcome': 'success',
          'duration_ms': elapsed.elapsedMilliseconds,
        },
      ),
    );
    return refreshed;
  }

  Future<void> _commit() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final saved = await _save();
      baseline = saved;
      await draftWork;
      await drafts.remove(widget.task.id);
      if (!mounted) return;
      setState(() => allowClose = true);
      if (widget.embedded) {
        widget.onSaved?.call(saved);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString()), showCloseIcon: true),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Salvataggio non riuscito. Il testo resta nell’editor.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  KeyEventResult _submitTitleFromKeyboard(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    unawaited(_commit());
    return KeyEventResult.handled;
  }

  Future<void> _saveAndExportToCalendar() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final saved = await _save();
      final result = await CalendarService(
        widget.repository.db,
      ).exportTask(saved);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      baseline = saved;
      await draftWork;
      await drafts.remove(widget.task.id);
      if (!mounted) return;
      setState(() => allowClose = true);
      if (widget.embedded) {
        widget.onSaved?.call(saved);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Aggiunta a ${result.calendarName}'),
          showCloseIcon: true,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message.toString()
          : 'Impossibile aggiungere al calendario.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.embedded || allowClose,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_closeWithDraft());
    },
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 40),
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: widget.embedded ? double.infinity : 460,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Focus(
                        key: const ValueKey('task-editor-title-keyboard'),
                        onKeyEvent: _submitTitleFromKeyboard,
                        child: TextField(
                          key: const ValueKey('task-editor-title'),
                          controller: title,
                          autofocus: !widget.embedded,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _commit(),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Cosa devi fare?',
                            prefixIcon: const Icon(Icons.check_circle_outline),
                            suffixIcon: PopupMenuButton<String>(
                              tooltip: 'Link nel titolo',
                              icon: const Icon(Icons.link),
                              onSelected: (value) {
                                if (value == 'add') {
                                  _addLinkToSelection(title);
                                } else if (!title.removeSelectedLink()) {
                                  _showSelectLinkedTextMessage();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'add',
                                  child: Text('Aggiungi link'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Togli link'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _compactActions(),
                      StreamBuilder<List<OutboxEntry>>(
                        stream:
                            (widget.repository.db.select(
                                  widget.repository.db.outboxEntries,
                                )..where(
                                  (r) => r.entityId.equals(widget.task.id),
                                ))
                                .watch(),
                        builder: (context, snapshot) {
                          final pending = snapshot.data ?? [];
                          final conflict = pending.any(
                            (e) =>
                                e.lastError == 'intent_conflict' ||
                                e.lastError == 'purged_entity',
                          );
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: Icon(
                                conflict
                                    ? Icons.sync_problem
                                    : pending.isEmpty
                                    ? Icons.check
                                    : Icons.cloud_upload_outlined,
                                size: 16,
                              ),
                              label: Text(
                                conflict
                                    ? 'Serve una scelta · apri storico'
                                    : pending.isEmpty
                                    ? 'Salvato sul dispositivo'
                                    : 'Salvato sul dispositivo · da sincronizzare',
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ActivityHistoryView(
                                    repository: widget.repository,
                                    entityId: widget.task.id,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('task-editor-description'),
                        controller: notes,
                        minLines: 2,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText:
                              'Aggiungi una descrizione o incolla un link…',
                          border: InputBorder.none,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _addLinkToSelection(notes),
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Aggiungi link'),
                        ),
                      ),
                      if (notes.links.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final link in notes.links)
                              InputChip(
                                label: Text(link.label),
                                tooltip: link.url,
                                avatar: const Icon(Icons.open_in_new, size: 16),
                                onPressed: () => launchUrl(
                                  Uri.parse(link.url),
                                  mode: LaunchMode.externalApplication,
                                ),
                                onDeleted: () =>
                                    setState(() => notes.removeLink(link)),
                              ),
                          ],
                        ),
                      if (draftRestored)
                        const Text(
                          'Bozza ripresa · non ancora salvata nell’attività',
                        ),
                      ExpansionTile(
                        dense: true,
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Progetto e sezione'),
                        children: [_projectFields()],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('task-editor-delete'),
                    onPressed: () async {
                      await widget.repository.softDelete(widget.task);
                      await drafts.remove(widget.task.id);
                      if (mounted) setState(() => allowClose = true);
                      if (!context.mounted) return;
                      AppUndo.show(
                        context,
                        message: 'Spostata nel cestino',
                        undo: () => widget.repository.restore(widget.task),
                      );
                      if (widget.embedded) {
                        widget.onDeleted?.call();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cestino'),
                  ),
                  if (!widget.embedded)
                    TextButton(
                      onPressed: _closeWithDraft,
                      child: const Text('Chiudi'),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('task-editor-save'),
                    onPressed: saving ? null : _commit,
                    icon: const Icon(Icons.check),
                    label: Text(saving ? 'Salvataggio' : 'Salva'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _compactActions() {
    const basic = <String>[
      'none',
      'calendar:day:1',
      'calendar:week:1',
      'calendar:month:1',
      'afterCompletion:day:1',
      'afterCompletion:week:1',
      'afterCompletion:month:1',
    ];
    final values = basic.contains(recurrence)
        ? basic
        : <String>[recurrence, ...basic];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(_compactDateLabel()),
            onPressed: _pickShowDate,
          ),
          if (showDate.text.isNotEmpty)
            IconButton(
              tooltip: 'Rimuovi data',
              visualDensity: VisualDensity.compact,
              onPressed: _clearShowDate,
              icon: const Icon(Icons.close, size: 18),
            ),
          ChoiceChip(
            key: const ValueKey('task-editor-no-date'),
            label: const Text('Senza data'),
            selected: showDate.text.isEmpty,
            onSelected: (_) => _clearShowDate(),
          ),
          PopupMenuButton<int>(
            tooltip: 'Priorità P${5 - priority}',
            icon: Icon(Icons.circle, color: _priorityColor(priority), size: 20),
            onSelected: (value) => setState(() => priority = value),
            itemBuilder: (context) => [
              for (var raw = 4; raw >= 1; raw--)
                PopupMenuItem(
                  value: raw,
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: _priorityColor(raw), size: 18),
                      const SizedBox(width: 10),
                      Text('P${5 - raw}'),
                    ],
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Ripetizione',
            icon: Icon(
              Icons.repeat,
              color: recurrence == 'none'
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
            ),
            onSelected: (value) => setState(() => recurrence = value),
            itemBuilder: (context) => [
              for (final value in values)
                PopupMenuItem(
                  value: value,
                  child: Text(
                    value == 'none'
                        ? 'Mai'
                        : recurrenceSmartLabel(value, showDate.text),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Altre azioni',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'calendar') _saveAndExportToCalendar();
              if (value == 'history') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ActivityHistoryView(
                      repository: widget.repository,
                      entityId: widget.task.id,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Text('Storico attività'),
              ),
              if (isAndroidPlatform)
                const PopupMenuItem(
                  value: 'calendar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_available_outlined),
                    title: Text('Aggiungi a Google Calendar'),
                  ),
                ),
            ],
          ),
          if (!widget.embedded)
            IconButton(
              tooltip: 'Chiudi',
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
        ],
      ),
    );
  }

  String _compactDateLabel() {
    if (showDate.text.isEmpty) return 'Data';
    try {
      return DateFormat(
        'd MMM',
        'it',
      ).format(CivilDate.parse(showDate.text).asLocalDate);
    } on FormatException {
      return 'Data';
    }
  }

  void _clearShowDate() {
    setState(() {
      showDate.clear();
      dateExplicitlyCleared = true;
    });
  }

  Future<void> _pickShowDate() async {
    final current = showDate.text.isEmpty
        ? DateTime.now()
        : CivilDate.parse(showDate.text).asLocalDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        showDate.text = CivilDate.fromDateTime(picked).toString();
        dateExplicitlyCleared = false;
      });
    }
  }

  void _showSelectLinkedTextMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleziona il testo collegato.'),
        showCloseIcon: true,
      ),
    );
  }

  Future<void> _addLinkToSelection(LinkTextEditingController controller) async {
    final value = await showDialog<({String url, String label})>(
      context: context,
      builder: (_) => TaskLinkDialog(selectedText: controller.selectedText),
    );
    if (value == null || !mounted) return;
    if (!controller.insertLink(value.url, label: value.label)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci un indirizzo valido.'),
          showCloseIcon: true,
        ),
      );
    } else {
      setState(() {});
    }
  }

  Widget _projectFields() => StreamBuilder<List<Project>>(
    stream: widget.repository.db.select(widget.repository.db.projects).watch(),
    builder: (context, projectSnapshot) => StreamBuilder<List<ProjectSection>>(
      stream: widget.repository.db
          .select(widget.repository.db.projectSections)
          .watch(),
      builder: (context, sectionSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final sections = (sectionSnapshot.data ?? const <ProjectSection>[])
            .where((item) => item.projectId == projectId && !item.isArchived)
            .toList();
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: projects.any((item) => item.id == projectId)
                    ? projectId
                    : null,
                decoration: const InputDecoration(labelText: 'Progetto'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuno')),
                  for (final project in projects.where(
                    (item) => !item.isArchived,
                  ))
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) => setState(() {
                  projectId = value;
                  projectSectionId = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue:
                    sections.any((item) => item.id == projectSectionId)
                    ? projectSectionId
                    : null,
                decoration: const InputDecoration(labelText: 'Sezione'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuna')),
                  for (final section in sections)
                    DropdownMenuItem(
                      value: section.id,
                      child: Text(section.name),
                    ),
                ],
                onChanged: projectId == null
                    ? null
                    : (value) => setState(() => projectSectionId = value),
              ),
            ),
          ],
        );
      },
    ),
  );
}
