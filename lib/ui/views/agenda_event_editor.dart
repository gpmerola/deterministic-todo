import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/editor_drafts.dart';
import '../../domain/agenda.dart';
import '../../domain/task.dart' show CivilDate;
import 'agenda_zone_picker.dart';

/// Event form with local recovery. When supplied, onSave must succeed before
/// closing; without it the result is only a proposal for the caller.
class AgendaEventEditor extends StatefulWidget {
  const AgendaEventEditor({
    required this.calendars,
    required this.initialStart,
    this.initialEnd,
    this.initialCalendarId,
    this.initialAllDay = false,
    this.existing,
    this.prefill,
    this.zoneLabel,
    this.notesEditable = true,
    this.heading,
    this.onSave,
    this.drafts,
    this.draftId,
    this.writesViaPhone = false,
    this.loadTimeZones,
    this.resolveTimeZone,
    super.key,
  });

  /// Title of the page when neither "Nuovo evento" nor "Modifica evento"
  /// fits, e.g. a copy edited in Todo only.
  final String? heading;
  final Future<void> Function(AgendaEventDraft)? onSave;
  final EditorDrafts? drafts;
  final String? draftId;
  final bool writesViaPhone;
  final Future<List<String>> Function()? loadTimeZones;
  final Future<AgendaEventDraft> Function(AgendaEventDraft)? resolveTimeZone;

  /// False when editing from the web: notes are not mirrored, so the field
  /// is hidden and the phone keeps the event's own notes.
  final bool notesEditable;

  /// Creation form pre-filled from a proposal (e.g. the AI assistant); the
  /// calendar stays selectable, unlike [existing].
  final AgendaEventDraft? prefill;

  /// When set the form edits this event: fields start from it and the
  /// calendar cannot change (moving between accounts is not supported).
  final AgendaEventDraft? existing;

  /// Recognised device zone, e.g. `Europe/London · UTC+1`; times are in it.
  final String? zoneLabel;

  /// Writable calendars only.
  final List<AgendaCalendar> calendars;
  final DateTime initialStart;

  /// End chosen by dragging on the timeline; an hour after the start
  /// otherwise.
  final DateTime? initialEnd;
  final String? initialCalendarId;
  final bool initialAllDay;

  @override
  State<AgendaEventEditor> createState() => _AgendaEventEditorState();
}

class _AgendaEventEditorState extends State<AgendaEventEditor>
    with WidgetsBindingObserver {
  /// Edited event, or a proposal to start a new one from.
  AgendaEventDraft? get _seed => widget.existing ?? widget.prefill;

  late final title = TextEditingController(text: _seed?.title);
  late final location = TextEditingController(text: _seed?.location);
  late final notes = TextEditingController(text: _seed?.notes);
  late String calendarId =
      _seed?.calendarId ??
      widget.initialCalendarId ??
      widget.calendars.firstOrNull?.id ??
      '';
  late bool allDay = _seed?.allDay ?? widget.initialAllDay;
  late final DateTime _start = _seed?.start ?? widget.initialStart;
  late final DateTime _end =
      _seed?.end ??
      widget.initialEnd ??
      widget.initialStart.add(const Duration(hours: 1));
  late DateTime day = DateTime(_start.year, _start.month, _start.day);
  // All-day ends are exclusive midnights: the last day is the one before.
  late DateTime lastDay = allDay
      ? DateTime(_end.year, _end.month, _end.day - 1)
      : DateTime(_end.year, _end.month, _end.day);
  late TimeOfDay startTime = TimeOfDay.fromDateTime(_start);
  late TimeOfDay endTime = TimeOfDay.fromDateTime(_end);
  AgendaRepeat repeat = AgendaRepeat.none;
  DateTime? repeatUntil;
  String? error;
  String? selectedZone;
  bool missingCalendar = false;
  bool _draftWriteFailed = false;
  bool saving = false;
  bool ready = false;
  bool leaving = false;
  bool restored = false;
  Timer? _timer;
  Future<void> _work = Future.value();
  late String _baseline;

  Map<String, dynamic> _state() => {
    'schema': 1,
    'zone': selectedZone,
    'title': title.text,
    'location': location.text,
    'notes': notes.text,
    'calendar': calendarId,
    'allDay': allDay,
    'day': day.toIso8601String(),
    'lastDay': lastDay.toIso8601String(),
    'start': startTime.hour * 60 + startTime.minute,
    'end': endTime.hour * 60 + endTime.minute,
    'repeat': repeat.name,
    'until': repeatUntil?.toIso8601String(),
  };
  bool get _dirty => jsonEncode(_state()) != _baseline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _baseline = jsonEncode(_state());
    for (final controller in [title, location, notes]) {
      controller.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    try {
      final value = widget.draftId == null
          ? null
          : await widget.drafts?.read(widget.draftId!);
      if (!mounted) return;
      if (value != null) {
        final resume = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Bozza non salvata'),
            content: const Text(
              'Riprendere la bozza locale? Verifica date e calendario prima di salvare.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Scarta bozza'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Riprendi'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (resume == true && value['schema'] == 1) {
          final selected = value['calendar'] as String;
          if (!widget.calendars.any((c) => c.id == selected)) {
            missingCalendar = true;
            error =
                'Il calendario della bozza non è disponibile: scegline uno prima di salvare.';
          } else {
            calendarId = selected;
          }
          title.text = value['title'] as String;
          location.text = value['location'] as String;
          notes.text = value['notes'] as String;
          selectedZone = value['zone'] as String?;
          allDay = value['allDay'] as bool;
          day = DateTime.parse(value['day'] as String);
          lastDay = DateTime.parse(value['lastDay'] as String);
          final start = value['start'] as int;
          final end = value['end'] as int;
          startTime = TimeOfDay(hour: start ~/ 60, minute: start % 60);
          endTime = TimeOfDay(hour: end ~/ 60, minute: end % 60);
          repeat = AgendaRepeat.values.byName(value['repeat'] as String);
          repeatUntil = DateTime.tryParse(value['until'] as String? ?? '');
          restored = true;
        } else {
          await widget.drafts?.remove(widget.draftId!);
        }
      }
    } catch (_) {
      error = 'Impossibile recuperare la bozza locale.';
    }
    if (mounted) setState(() => ready = true);
  }

  void _changed() {
    if (!ready || saving || leaving) return;
    setState(() {});
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!ready || saving || leaving) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), _persist);
  }

  Future<void> _persist() async {
    _timer?.cancel();
    if (!ready || leaving || widget.drafts == null || widget.draftId == null) {
      return;
    }
    final value = _state();
    final dirty = _dirty;
    _work = _work
        .then((_) async {
          if (dirty) {
            await widget.drafts!.write(widget.draftId!, value);
          } else {
            await widget.drafts!.remove(widget.draftId!);
          }
          _draftWriteFailed = false;
        })
        .catchError((Object _) {
          _draftWriteFailed = true;
          if (mounted) {
            super.setState(
              () => error = 'Bozza non conservata: resta qui e riprova.',
            );
          }
        });
    await _work;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_persist());
  }

  Future<void> _close() async {
    if (saving || !ready) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Modifiche non salvate'),
          content: Text(
            widget.drafts == null
                ? 'Scartare le modifiche alla proposta?'
                : 'Uscire conservando la bozza su questo dispositivo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continua a modificare'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                widget.drafts == null ? 'Scarta ed esci' : 'Conserva ed esci',
              ),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      await _persist();
      if (_draftWriteFailed) return;
    }
    if (mounted) {
      setState(() => leaving = true);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    title.dispose();
    location.dispose();
    notes.dispose();
    super.dispose();
  }

  AgendaEventDraft _draft() {
    DateTime timed(int y, int m, int d, int h, int min) => selectedZone == null
        ? DateTime(y, m, d, h, min)
        : DateTime.utc(y, m, d, h, min);
    final start = allDay
        ? day
        : timed(day.year, day.month, day.day, startTime.hour, startTime.minute);
    final end = allDay
        ? DateTime(lastDay.year, lastDay.month, lastDay.day + 1)
        : timed(
            lastDay.year,
            lastDay.month,
            lastDay.day,
            endTime.hour,
            endTime.minute,
          );

    return AgendaEventDraft(
      calendarId: calendarId,
      timeZone: allDay ? null : selectedZone,
      title: title.text,
      start: start,
      end: end,
      allDay: allDay,
      location: location.text,
      notes: notes.text,
      repeat: widget.existing == null ? repeat : AgendaRepeat.none,
      repeatUntil: repeat == AgendaRepeat.none || repeatUntil == null
          ? null
          : CivilDate.fromDateTime(repeatUntil!),
    );
  }

  Future<void> _pickRepeatUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: repeatUntil ?? day.add(const Duration(days: 30)),
      firstDate: day,
      lastDate: DateTime(day.year + 10),
      helpText: 'Ripeti fino al',
    );
    if (picked != null) setState(() => repeatUntil = picked);
  }

  Future<void> _save() async {
    if (saving || !ready || missingCalendar) return;
    final draft = _draft();
    final problem = draft.problem;
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    await _persist();
    if (!mounted) return;
    try {
      final resolved = widget.resolveTimeZone == null
          ? draft
          : await widget.resolveTimeZone!(draft);
      await widget.onSave?.call(resolved);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              failure is PlatformException &&
                  failure.code == 'invalid_local_time'
              ? 'Orario inesistente o ambiguo nel fuso scelto: scegli un altro orario.'
              : 'Salvataggio non riuscito. I campi sono conservati: riprova.';
        });
      }
      return;
    }
    // The write succeeded: never repeat it because draft cleanup failed.
    _timer?.cancel();
    await _work;
    try {
      if (widget.draftId != null) await widget.drafts?.remove(widget.draftId!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Evento salvato; impossibile rimuovere la bozza locale.',
            ),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => leaving = true);
      Navigator.of(context).pop(draft);
    }
  }

  Future<void> _pickZone() async {
    try {
      final zones = await widget.loadTimeZones!();
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => AgendaZonePicker(zones: zones),
      );
      if (chosen != null && mounted) setState(() => selectedZone = chosen);
    } catch (_) {
      if (mounted) setState(() => error = 'Impossibile leggere i fusi orari.');
    }
  }

  Future<void> _pickDay({required bool last}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: last ? lastDay : day,
      firstDate: DateTime(day.year - 5),
      lastDate: DateTime(day.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (last) {
        lastDay = picked.isBefore(day) ? day : picked;
      } else {
        final span = lastDay.difference(day);
        day = picked;
        lastDay = picked.add(span);
      }
    });
  }

  Future<void> _pickTime({required bool end}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: end ? endTime : startTime,
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        endTime = picked;
      } else {
        final duration =
            DateTime.utc(
              lastDay.year,
              lastDay.month,
              lastDay.day,
              endTime.hour,
              endTime.minute,
            ).difference(
              DateTime.utc(
                day.year,
                day.month,
                day.day,
                startTime.hour,
                startTime.minute,
              ),
            );
        startTime = picked;
        final end = DateTime.utc(
          day.year,
          day.month,
          day.day,
          picked.hour,
          picked.minute,
        ).add(duration > Duration.zero ? duration : const Duration(hours: 1));
        lastDay = DateTime(end.year, end.month, end.day);
        endTime = TimeOfDay.fromDateTime(end);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('EEE d MMM yyyy', 'it');
    String time(TimeOfDay value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    final target = widget.calendars
        .where((c) => c.id == calendarId)
        .firstOrNull;
    final duration = _draft().end.difference(_draft().start);
    return PopScope(
      canPop: leaving || (ready && !saving && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Annulla',
            icon: const Icon(Icons.close),
            onPressed: saving ? null : _close,
          ),
          title: Text(
            widget.heading ??
                (widget.existing == null ? 'Nuovo evento' : 'Modifica evento'),
          ),
          actions: [
            TextButton(
              key: const ValueKey('agenda-event-save'),
              onPressed:
                  !ready ||
                      saving ||
                      missingCalendar ||
                      widget.calendars.isEmpty
                  ? null
                  : _save,
              child: Text(saving ? 'Salvataggio…' : 'Salva'),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: saving || !ready,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                widget.onSave == null
                    ? 'Proposta · nessun evento creato'
                    : widget.writesViaPhone
                    ? 'Da applicare sul telefono · ${target?.name ?? "Scegli un calendario"}'
                    : target?.localOnly == true
                    ? 'Copia personale in Todo · backup Calendario se attivo'
                    : 'Salvi nel calendario ${target?.name ?? "selezionato"}',
                key: const ValueKey('agenda-save-destination'),
              ),
              if (widget.heading == 'Modifica solo in Todo')
                const Text(
                  'Crea una copia personale e nasconde qui l’originale. Le modifiche future dell’originale non aggiornano la copia.',
                ),
              if (restored) const Text('Bozza locale ripristinata'),
              const SizedBox(height: 8),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextField(
                key: const ValueKey('agenda-event-title'),
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Titolo'),
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              if (widget.calendars.isEmpty)
                const Text('Nessun calendario modificabile sul telefono.')
              else
                DropdownButtonFormField<String>(
                  key: const ValueKey('agenda-event-calendar'),
                  initialValue: calendarId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Calendario'),
                  items: [
                    for (final calendar in widget.calendars)
                      DropdownMenuItem(
                        value: calendar.id,
                        child: Text(
                          calendar.name == calendar.accountName ||
                                  calendar.accountName.isEmpty
                              ? calendar.name
                              : '${calendar.name} · ${calendar.accountName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: widget.existing != null
                      ? null
                      : (value) => setState(() {
                          calendarId = value ?? '';
                          missingCalendar = false;
                        }),
                ),
              SwitchListTile(
                key: const ValueKey('agenda-event-all-day'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Tutto il giorno'),
                value: allDay,
                onChanged: (value) => setState(() => allDay = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(dayFormat.format(day)),
                trailing: allDay
                    ? null
                    : TextButton(
                        key: const ValueKey('agenda-event-start'),
                        onPressed: () => _pickTime(end: false),
                        child: Text(time(startTime)),
                      ),
                onTap: () => _pickDay(last: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.east),
                title: Text('Fine · ${dayFormat.format(lastDay)}'),
                trailing: allDay
                    ? null
                    : TextButton(
                        key: const ValueKey('agenda-event-end'),
                        onPressed: () => _pickTime(end: true),
                        child: Text(time(endTime)),
                      ),
                onTap: () => _pickDay(last: true),
              ),
              if (!allDay)
                Text(
                  duration <= Duration.zero
                      ? 'La fine deve essere dopo l’inizio.'
                      : 'Durata${selectedZone == null ? '' : ' nominale'}: ${duration.inHours} h ${duration.inMinutes.remainder(60)} min',
                  key: const ValueKey('agenda-event-duration'),
                ),
              if (widget.existing == null) ...[
                DropdownButtonFormField<AgendaRepeat>(
                  key: const ValueKey('agenda-event-repeat'),
                  initialValue: repeat,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ripeti',
                    prefixIcon: Icon(Icons.repeat),
                  ),
                  items: [
                    for (final option in AgendaRepeat.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(
                          agendaRepeatLabel(option, day),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => repeat = value ?? AgendaRepeat.none),
                ),
                if (repeat != AgendaRepeat.none)
                  ListTile(
                    key: const ValueKey('agenda-event-repeat-until'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text(
                      repeatUntil == null
                          ? 'Senza fine'
                          : 'Fino al ${dayFormat.format(repeatUntil!)}',
                    ),
                    trailing: repeatUntil == null
                        ? null
                        : IconButton(
                            tooltip: 'Senza fine',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => repeatUntil = null),
                          ),
                    onTap: _pickRepeatUntil,
                  ),
                const SizedBox(height: 8),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.public, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        allDay
                            ? 'Giornata intera: stessa data in ogni fuso'
                            : 'Fuso orario: ${selectedZone ?? widget.zoneLabel ?? 'non riconosciuto'}',
                        key: const ValueKey('agenda-event-zone'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (!allDay &&
                  widget.loadTimeZones != null &&
                  widget.existing == null)
                TextButton(
                  onPressed: _pickZone,
                  child: const Text('Scegli fuso orario'),
                ),
              TextField(
                controller: location,
                decoration: const InputDecoration(
                  labelText: 'Luogo (facoltativo)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              if (widget.notesEditable) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Note (facoltative)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
