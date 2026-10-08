import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/agenda.dart';
import '../domain/ai_capture.dart';
import '../domain/task.dart';
import '../services/ai_settings.dart';
import 'views/agenda_event_editor.dart';

/// "Scrivi o detta": one note becomes tasks and/or events. Nothing is sent
/// until the user taps Interpreta, and nothing is created until they confirm
/// the reviewed proposals. Created items carry the ✨ marker.
class AiCapturePage extends StatefulWidget {
  const AiCapturePage({
    required this.client,
    required this.providerLabel,
    required this.loadContext,
    required this.create,
    this.calendarColors = const {},
    super.key,
  });

  /// Colours of the phone calendars, for the proposal cards.
  final Map<String, Color?> calendarColors;

  final AiClient client;
  final String providerLabel;
  final Future<AiCaptureContext> Function() loadContext;

  /// Writes the confirmed proposals; returns how many were created.
  final Future<int> Function(List<AiProposal> items) create;

  @override
  State<AiCapturePage> createState() => _AiCapturePageState();
}

class _AiCapturePageState extends State<AiCapturePage> {
  final input = TextEditingController();
  AiCaptureContext? context_;
  List<AiProposal> proposals = const [];
  final Set<int> selected = {};
  String? note;
  String? error;
  int dropped = 0;
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _interpret() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ctx = await widget.loadContext();
      final raw = await widget.client.completeJson(
        system: aiCaptureSystemPrompt(),
        user: aiCaptureUserPrompt(ctx, text),
      );
      final result = parseAiCapture(raw, ctx);
      if (!mounted) return;
      setState(() {
        context_ = ctx;
        proposals = result.items;
        selected
          ..clear()
          ..addAll([for (var i = 0; i < result.items.length; i++) i]);
        note = result.note;
        dropped = result.dropped;
        busy = false;
        if (result.items.isEmpty) {
          error = 'Nessuna attività o evento riconosciuto: riformula.';
        }
      });
    } on AiException catch (failure) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = failure.message;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = const AiException(AiFailure.badResponse).message;
      });
    }
  }

  Future<void> _edit(int index) async {
    final item = proposals[index];
    final AiProposal? next = item.kind == AiProposalKind.event
        ? await _editEvent(item)
        : await _editTask(item);
    if (next == null || !mounted) return;
    setState(() {
      proposals = [...proposals]..[index] = next;
    });
  }

  Future<AiProposal?> _editEvent(AiProposal item) async {
    final draft = await Navigator.of(context).push<AgendaEventDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AgendaEventEditor(
          // The writable calendars sent as context: the proposal's calendar
          // is always among them.
          calendars: [
            for (final calendar
                in context_?.calendars ?? const <({String id, String name})>[])
              AgendaCalendar(
                id: calendar.id,
                name: calendar.name,
                accountName: '',
                writable: true,
              ),
          ],
          initialStart: item.start!,
          zoneLabel: context_?.zoneLabel,
          prefill: AgendaEventDraft(
            calendarId: item.calendarId!,
            title: item.title,
            start: item.start!,
            end: item.end!,
            allDay: item.allDay,
            location: item.location,
            notes: item.notes,
          ),
        ),
      ),
    );
    if (draft == null) return null;
    return AiProposal.event(
      title: draft.title.trim(),
      start: draft.start,
      end: draft.end,
      allDay: draft.allDay,
      calendarId: draft.calendarId,
      location: draft.location,
      notes: draft.notes,
      relatedEvent: item.relatedEvent,
    );
  }

  Future<AiProposal?> _editTask(AiProposal item) async {
    final title = TextEditingController(text: item.title);
    var date = item.date;
    final result = await showDialog<AiProposal>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Attività'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('ai-task-title'),
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titolo'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  date == null
                      ? 'Senza data'
                      : DateFormat(
                          'EEE d MMM yyyy',
                          'it',
                        ).format(date!.asLocalDate),
                ),
                trailing: date == null
                    ? null
                    : IconButton(
                        tooltip: 'Senza data',
                        icon: const Icon(Icons.close),
                        onPressed: () => setDialogState(() => date = null),
                      ),
                onTap: () async {
                  final today = DateTime.now();
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: date?.asLocalDate ?? today,
                    firstDate: DateTime(today.year - 1),
                    lastDate: DateTime(today.year + 5),
                  );
                  if (picked != null) {
                    setDialogState(() => date = CivilDate.fromDateTime(picked));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      dialogContext,
                      AiProposal.task(
                        title: title.text.trim(),
                        date: date,
                        projectId: item.projectId,
                        notes: item.notes,
                        relatedEvent: item.relatedEvent,
                      ),
                    ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    return result;
  }

  Future<void> _create() async {
    final chosen = [
      for (var i = 0; i < proposals.length; i++)
        if (selected.contains(i)) proposals[i],
    ];
    if (chosen.isEmpty) return;
    setState(() => busy = true);
    try {
      final created = await widget.create(chosen);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on Object {
      // Not logged: proposals carry the user's text.
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Creazione non riuscita: nessun elemento perso, riprova.';
      });
    }
  }

  String _when(AiProposal item) {
    if (item.kind == AiProposalKind.task) {
      return item.date == null
          ? 'Senza data'
          : DateFormat('EEE d MMM', 'it').format(item.date!.asLocalDate);
    }
    final day = DateFormat('EEE d MMM', 'it');
    if (item.allDay) {
      final last = item.end!.subtract(const Duration(days: 1));
      return last.isAfter(item.start!)
          ? '${day.format(item.start!)} – ${day.format(last)}'
          : '${day.format(item.start!)} · tutto il giorno';
    }
    final clock = DateFormat.Hm('it');
    return '${day.format(item.start!)} · '
        '${clock.format(item.start!)}–${clock.format(item.end!)}';
  }

  String? _where(AiProposal item) {
    final ctx = context_;
    if (ctx == null) return null;
    if (item.kind == AiProposalKind.task) {
      return ctx.projects
          .where((p) => p.id == item.projectId)
          .map((p) => p.name)
          .firstOrNull;
    }
    return ctx.calendars
        .where((c) => c.id == item.calendarId)
        .map((c) => shortCalendarName(c.name))
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reviewing = proposals.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('✨ Assistente')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            key: const ValueKey('ai-capture-input'),
            controller: input,
            autofocus: !reviewing,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Scrivi o detta (microfono della tastiera)',
              hintText:
                  'Es. preparare slide per la riunione TNG di giovedì; '
                  'visita Maudsley martedì 15–16',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Premendo Interpreta il testo, la data di oggi, i nomi dei '
            'progetti e dei calendari e gli eventi dei prossimi 14 giorni '
            'vengono inviati a ${widget.providerLabel}. Niente viene creato '
            'senza conferma; gli elementi creati iniziano con ✨.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('ai-capture-interpret'),
            onPressed: busy ? null : _interpret,
            icon: busy && !reviewing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(reviewing ? 'Interpreta di nuovo' : 'Interpreta'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                key: const ValueKey('ai-capture-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('ℹ️ $note', style: theme.textTheme.bodyMedium),
            ),
          if (reviewing) ...[
            const SizedBox(height: 16),
            Text('Da creare', style: theme.textTheme.titleSmall),
            if (dropped > 0)
              Text(
                '$dropped proposte scartate perché non valide.',
                style: theme.textTheme.bodySmall,
              ),
            for (final (index, item) in proposals.indexed)
              Card(
                key: ValueKey('ai-proposal-$index'),
                child: CheckboxListTile(
                  // Checkbox left, title full width, edit right.
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.only(left: 4, right: 4),
                  value: selected.contains(index),
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          value == true
                              ? selected.add(index)
                              : selected.remove(index);
                        }),
                  secondary: IconButton(
                    tooltip: 'Modifica',
                    onPressed: busy ? null : () => _edit(index),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  title: Text(markAiTitle(item.title)),
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        // Calendar colour dot before its short name.
                        if (item.kind == AiProposalKind.event)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color:
                                    widget.calendarColors[item.calendarId] ??
                                    theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        TextSpan(
                          text: [
                            item.kind == AiProposalKind.task
                                ? '☐ Attività'
                                : 'Evento',
                            _when(item),
                            ?_where(item),
                            if (item.location != null) item.location!,
                            if (item.relatedEvent != null)
                              'per ${item.relatedEvent}',
                          ].join(' · '),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('ai-capture-create'),
              onPressed: busy || selected.isEmpty ? null : _create,
              child: Text(
                'Crea ${selected.length} '
                '${selected.length == 1 ? 'elemento' : 'elementi'}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
