import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';

/// Full-screen form for a new phone calendar event. Returns the draft, or
/// null when dismissed; the caller writes it.
class AgendaEventEditor extends StatefulWidget {
  const AgendaEventEditor({
    required this.calendars,
    required this.initialStart,
    this.initialCalendarId,
    this.initialAllDay = false,
    super.key,
  });

  /// Writable calendars only.
  final List<AgendaCalendar> calendars;
  final DateTime initialStart;
  final String? initialCalendarId;
  final bool initialAllDay;

  @override
  State<AgendaEventEditor> createState() => _AgendaEventEditorState();
}

class _AgendaEventEditorState extends State<AgendaEventEditor> {
  final title = TextEditingController();
  final location = TextEditingController();
  final notes = TextEditingController();
  late String calendarId =
      widget.initialCalendarId ?? widget.calendars.firstOrNull?.id ?? '';
  late bool allDay = widget.initialAllDay;
  late DateTime day = DateTime(
    widget.initialStart.year,
    widget.initialStart.month,
    widget.initialStart.day,
  );
  late DateTime lastDay = day;
  late TimeOfDay startTime = TimeOfDay.fromDateTime(widget.initialStart);
  late TimeOfDay endTime = TimeOfDay.fromDateTime(
    widget.initialStart.add(const Duration(hours: 1)),
  );
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
    );
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
        title: const Text('Nuovo evento'),
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
              onChanged: (value) => setState(() => calendarId = value ?? ''),
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
