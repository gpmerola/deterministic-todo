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
  bool saving = false;

  bool _matchesTask(Task task) =>
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
      final parsed = const QuickAddParser().parse(title.text);
      title.text = parsed.title;
      if (parsed.showDate != null) {
        showDate.text = parsed.showDate.toString();
      }
      if (parsed.recurrence != null) recurrence = parsed.recurrence!;
    }
    await widget.repository.updateDetails(
      widget.task,
      title: title.toMarkdown(),
      notes: notes.text.trim().isEmpty ? null : notes.toMarkdown().trim(),
      showDate: showDate.text.trim().isEmpty
          ? null
          : CivilDate.parse(showDate.text.trim()).toString(),
      recurrence: recurrence == 'none' ? null : recurrence,
      priority: priority,
      projectId: projectId,
      sectionId: projectSectionId,
      updateProject: true,
    );
    var refreshed = await (widget.repository.db.select(
      widget.repository.db.tasks,
    )..where((row) => row.id.equals(widget.task.id))).getSingle();
    final plannedDate = showDate.text.trim().isEmpty
        ? null
        : CivilDate.parse(showDate.text.trim());
    final today = CivilDate.fromDateTime(DateTime.now());
    final derivedStatus = plannedDate == null
        ? TaskStatus.inbox
        : plannedDate.compareTo(today) <= 0
        ? TaskStatus.available
        : TaskStatus.scheduled;
    if (derivedStatus.name != refreshed.status) {
      await widget.repository.move(refreshed, derivedStatus);
      refreshed = await (widget.repository.db.select(
        widget.repository.db.tasks,
      )..where((row) => row.id.equals(widget.task.id))).getSingle();
    }
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
      if (!mounted) return;
      if (widget.embedded) {
        widget.onSaved?.call(saved);
      } else {
        Navigator.pop(context);
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString()), showCloseIcon: true),
      );
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
    try {
      final saved = await _save();
      final result = await CalendarService(
        widget.repository.db,
      ).exportTask(saved);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
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
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
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
                    ExpansionTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      leading: const Icon(Icons.tune),
                      title: const Text('Altri dettagli'),
                      children: [
                        TextField(
                          controller: notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Note'),
                        ),
                        if (notes.links.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                for (final link in notes.links)
                                  InputChip(
                                    avatar: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    label: Text(link.label),
                                    tooltip: link.url,
                                    onPressed: () => launchUrl(
                                      Uri.parse(link.url),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    onDeleted: () =>
                                        setState(() => notes.removeLink(link)),
                                  ),
                              ],
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () => _addLinkToSelection(notes),
                                icon: const Icon(Icons.link, size: 18),
                                label: const Text('Aggiungi link'),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  if (!notes.removeSelectedLink()) {
                                    _showSelectLinkedTextMessage();
                                  }
                                },
                                icon: const Icon(Icons.link_off, size: 18),
                                label: const Text('Togli link'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _projectFields(),
                      ],
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
              onPressed: () => setState(showDate.clear),
              icon: const Icon(Icons.close, size: 18),
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
          if (isAndroidPlatform)
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'calendar') _saveAndExportToCalendar();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
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
      setState(() => showDate.text = CivilDate.fromDateTime(picked).toString());
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
    if (controller.selectedText?.trim().isEmpty ?? true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prima seleziona il testo da collegare.'),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final url = TextEditingController(text: 'https://');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi link'),
        content: TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Indirizzo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, url.text),
            child: const Text('Collega'),
          ),
        ],
      ),
    );
    url.dispose();
    if (value == null || !mounted) return;
    if (!controller.addLink(value)) {
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
