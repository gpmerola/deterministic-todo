import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/task.dart' show CivilDate;

/// Full-screen form for a new phone calendar event. Returns the draft, or
/// null when dismissed; the caller writes it.
class AgendaEventEditor extends StatefulWidget {
  const AgendaEventEditor({
    required this.calendars,
    required this.initialStart,
    this.initialCalendarId,
    this.initialAllDay = false,
    this.existing,
    this.prefill,
    this.zoneLabel,
    super.key,
  });

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
  final String? initialCalendarId;
  final bool initialAllDay;

  @override
  State<AgendaEventEditor> createState() => _AgendaEventEditorState();
}

class _AgendaEventEditorState extends State<AgendaEventEditor> {
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
      _seed?.end ?? widget.initialStart.add(const Duration(hours: 1));
  late DateTime day = DateTime(_start.year, _start.month, _start.day);
  // All-day ends are exclusive midnights: the last day is the one before.
  late DateTime lastDay = allDay
      ? DateTime(_end.year, _end.month, _end.day - 1)
      : day;
  late TimeOfDay startTime = TimeOfDay.fromDateTime(_start);
  late TimeOfDay endTime = TimeOfDay.fromDateTime(_end);
  AgendaRepeat repeat = AgendaRepeat.none;
  DateTime? repeatUntil;
  String? error;

  @override
  void dispose() {
    title.dispose();
    location.dispose();
    notes.dispose();
    super.dispose();
  }

  AgendaEventDraft _draft() {
    final start = allDay
        ? day
        : DateTime(
            day.year,
            day.month,
            day.day,
            startTime.hour,
            startTime.minute,
          );
    var end = allDay
        ? DateTime(lastDay.year, lastDay.month, lastDay.day + 1)
        : DateTime(day.year, day.month, day.day, endTime.hour, endTime.minute);
    // An end time before the start means the event runs past midnight.
    if (!allDay && !end.isAfter(start)) {
      end = DateTime(end.year, end.month, end.day + 1, end.hour, end.minute);
    }
    return AgendaEventDraft(
      calendarId: calendarId,
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

  void _save() {
    final draft = _draft();
    final problem = draft.problem;
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    Navigator.of(context).pop(draft);
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
        // Keep the duration when the start moves, like Google Calendar.
        final duration =
            (endTime.hour * 60 + endTime.minute) -
            (startTime.hour * 60 + startTime.minute);
        startTime = picked;
        final minutes =
            (picked.hour * 60 +
                picked.minute +
                (duration > 0 ? duration : 60)) %
            (24 * 60);
        endTime = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('EEE d MMM yyyy', 'it');
    String time(TimeOfDay value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annulla',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.existing == null ? 'Nuovo evento' : 'Modifica evento',
        ),
        actions: [
          TextButton(
            key: const ValueKey('agenda-event-save'),
            onPressed: widget.calendars.isEmpty ? null : _save,
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
                  : (value) => setState(() => calendarId = value ?? ''),
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
            title: allDay
                ? Text(dayFormat.format(lastDay))
                : const Text('Fine'),
            trailing: allDay
                ? null
                : TextButton(
                    key: const ValueKey('agenda-event-end'),
                    onPressed: () => _pickTime(end: true),
                    child: Text(time(endTime)),
                  ),
            onTap: allDay ? () => _pickDay(last: true) : null,
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
                        : 'Fuso orario: ${widget.zoneLabel ?? 'non riconosciuto'}',
                    key: const ValueKey('agenda-event-zone'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: location,
            decoration: const InputDecoration(
              labelText: 'Luogo (facoltativo)',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
