import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/editor_drafts.dart';
import '../data/local/database.dart';
import '../domain/quick_add_metadata.dart';
import '../domain/quick_add_parser.dart';
import '../domain/task.dart';
import '../services/diagnostic_log_service.dart';
import 'priority_color.dart';
import 'smart_date_text_controller.dart';

({String? summary, String? error}) _quickAddPreview(
  String value, {
  required int priority,
  required String? projectId,
  required List<Project> projects,
}) {
  final metadata = parseQuickAddMetadata(
    value,
    defaultPriority: priority,
    defaultProjectId: projectId,
    projectsByName: {
      for (final project in projects.where((item) => !item.isArchived))
        project.name: project.id,
    },
  );
  final projectNames = {
    for (final project in projects) project.id: project.name,
  };
  try {
    final now = DateTime.now();
    final draft = const QuickAddParser().parse(metadata.text, now: now);
    final date = draft.showDate ?? CivilDate.fromDateTime(now);
    final parts = <String>[
      DateFormat('EEE d MMM yyyy', 'it').format(date.asLocalDate),
      if (draft.recurrence != null)
        recurrenceSmartLabel(draft.recurrence, date.toString()),
      projectNames[metadata.projectId] ?? 'Nessun progetto',
      metadata.priority == 1
          ? 'Nessuna priorità'
          : 'Priorità P${5 - metadata.priority}',
    ];
    return (summary: parts.join(' · '), error: null);
  } on FormatException catch (error) {
    return (summary: null, error: value.trim().isEmpty ? null : error.message);
  }
}

/// Text and choices of one quick-add submission.
typedef QuickAddInput = ({
  String text,
  String notes,
  int priority,
  String? projectId,
  String? sectionId,
});

/// Bottom sheet composer. [onSubmit] creates the item and returns false to
/// keep the sheet open (invalid input). An unsent draft is kept locally in
/// [draftStore], never synced.
Future<void> showQuickAddSheet(
  BuildContext context, {
  required List<Project> projects,
  required EditorDrafts draftStore,
  required Future<bool> Function(QuickAddInput input) onSubmit,
  String? projectId,
  String? sectionId,
}) async {
  final openElapsed = Stopwatch()..start();
  var openLogged = false;
  final availableProjects = List<Project>.of(projects);
  final draft = await draftStore.read('quick_add');
  if (!context.mounted) return;
  final controller = SmartDateTextController()
    ..text = draft?['title'] as String? ?? '';
  final notesController = TextEditingController(
    text: draft?['notes'] as String? ?? '',
  );
  projectId = draft?['projectId'] as String? ?? projectId;
  sectionId = draft?['sectionId'] as String? ?? sectionId;
  var submitted = false;
  var submitting = false;
  final titleFocusNode = FocusNode(debugLabel: 'quick-add-title');
  var keyboardWasVisible = false;
  var stableKeyboardInset = 0.0;
  var closing = false;
  var showNotes = notesController.text.isNotEmpty;
  // Ogni nuova attività parte senza priorità, indipendentemente dalla scelta
  // usata nel composer precedente.
  var priority = draft?['priority'] as int? ?? 1;
  // Let Android begin opening the IME in the same frame as the composer.
  titleFocusNode.requestFocus();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    requestFocus: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration.zero,
      reverseDuration: Duration.zero,
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        if (!openLogged) {
          openLogged = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            openElapsed.stop();
            unawaited(
              DiagnosticLogService.instance.event(
                'interaction_latency',
                fields: {
                  'interaction': 'composer_open',
                  'outcome': 'visible',
                  'duration_ms': openElapsed.elapsedMilliseconds,
                },
              ),
            );
          });
        }
        final currentKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        if (currentKeyboardInset > 0) {
          keyboardWasVisible = true;
          if (currentKeyboardInset > stableKeyboardInset) {
            stableKeyboardInset = currentKeyboardInset;
          }
        } else if (keyboardWasVisible && !closing && !submitting) {
          closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          });
        }
        final composerInset = keyboardWasVisible
            ? stableKeyboardInset
            : currentKeyboardInset;
        final desktopComposer = MediaQuery.sizeOf(context).width >= 900;
        final preview = _quickAddPreview(
          controller.text,
          priority: priority,
          projectId: projectId,
          projects: availableProjects,
        );
        final canSubmit =
            controller.text.trim().isNotEmpty && preview.error == null;
        Future<void> submit() async {
          if (submitting || controller.text.trim().isEmpty) return;
          // Enter may arrive before the rebuild triggered by the last keystroke.
          final latest = _quickAddPreview(
            controller.text,
            priority: priority,
            projectId: projectId,
            projects: availableProjects,
          );
          if (latest.error != null) return;
          setSheetState(() => submitting = true);
          try {
            if (await onSubmit((
                  text: controller.text,
                  notes: notesController.text,
                  priority: priority,
                  projectId: projectId,
                  sectionId: sectionId,
                )) &&
                sheetContext.mounted) {
              submitted = true;
              controller.clear();
              await draftStore.remove('quick_add');
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            }
          } finally {
            if (sheetContext.mounted) {
              setSheetState(() {
                submitting = false;
                if (!submitted) keyboardWasVisible = false;
              });
            }
          }
        }

        return Padding(
          key: const ValueKey('mobile-quick-add-keyboard-padding'),
          padding: EdgeInsets.fromLTRB(16, 0, 16, composerInset + 12),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('mobile-quick-add-field'),
                  controller: controller,
                  readOnly: submitting,
                  focusNode: titleFocusNode,
                  minLines: 1,
                  maxLines: desktopComposer ? 1 : 3,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setSheetState(() {}),
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: 'Cosa devi fare?',
                    helperText: preview.summary,
                    helperMaxLines: 4,
                    errorText: preview.error,
                    errorMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('mobile-quick-add-notes'),
                      tooltip: 'Aggiungi descrizione',
                      onPressed: () => setSheetState(() {
                        showNotes = !showNotes;
                      }),
                      icon: Icon(
                        Icons.notes_outlined,
                        color: showNotes
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    PopupMenuButton<int>(
                      key: const ValueKey('mobile-quick-add-priority'),
                      tooltip: priority == 1
                          ? 'Nessuna priorità'
                          : 'Priorità P${5 - priority}',
                      icon: Icon(
                        Icons.circle,
                        size: 20,
                        color: priorityColor(priority),
                      ),
                      onSelected: (value) =>
                          setSheetState(() => priority = value),
                      itemBuilder: (_) => [
                        for (var raw = 4; raw >= 1; raw--)
                          PopupMenuItem(
                            value: raw,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 18,
                                  color: priorityColor(raw),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  raw == 1 ? 'Nessuna priorità' : 'P${5 - raw}',
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (availableProjects.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: 'Progetto',
                        icon: Icon(
                          projectId == null
                              ? Icons.folder_outlined
                              : Icons.folder,
                          color: projectId == null
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                        onSelected: (value) => setSheetState(
                          () => projectId = value.isEmpty ? null : value,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem<String>(
                            value: '',
                            child: Text('Nessun progetto'),
                          ),
                          for (final project in availableProjects)
                            PopupMenuItem<String>(
                              value: project.id,
                              child: Text(project.name),
                            ),
                        ],
                      ),
                    const Spacer(),
                    IconButton.filled(
                      key: const ValueKey('mobile-quick-add-submit'),
                      tooltip: 'Aggiungi attività',
                      onPressed: submitting || !canSubmit ? null : submit,
                      icon: submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Salvataggio in corso',
                              ),
                            )
                          : const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
                if (showNotes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextField(
                      key: const ValueKey('mobile-quick-add-notes-field'),
                      controller: notesController,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Descrizione',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (!submitted &&
      (controller.text.trim().isNotEmpty ||
          notesController.text.trim().isNotEmpty)) {
    await draftStore.write('quick_add', {
      'schema': 1,
      'title': controller.text,
      'notes': notesController.text,
      'projectId': projectId,
      'sectionId': sectionId,
      'priority': priority,
    });
  }
  // The route completes while its exit animation can still own the field for
  // one frame. Dispose after that frame to avoid a controller-after-dispose
  // race on fast submissions.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.dispose();
    notesController.dispose();
    titleFocusNode.dispose();
  });
}
