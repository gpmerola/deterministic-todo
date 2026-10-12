import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import 'agenda_event_flows.dart' show parseCalendarColor;

final class AgendaPickerResult {
  const AgendaPickerResult(
    this.hidden,
    this.filter, {
    this.eventCalendarId,
    this.aiEventCalendarId,
    this.colors,
  });

  /// User colours by calendar id; null when the picker did not offer them.
  final Map<String, String>? colors;

  /// Separate calendar for ✨ events; null means "same as new events".
  final String? aiEventCalendarId;
  final Set<String> hidden;
  final AgendaFilter filter;

  /// Calendar for new events (+ and ✨ assistant).
  final String? eventCalendarId;
}

class AgendaCalendarPicker extends StatefulWidget {
  const AgendaCalendarPicker({
    required this.calendars,
    required this.hidden,
    this.filter = AgendaFilter.none,
    this.eventCalendarId,
    this.aiEventCalendarId,
    this.colors,
    super.key,
  });

  /// Colours the user picked; null hides the colour choice.
  final Map<String, String>? colors;

  final String? aiEventCalendarId;
  final List<AgendaCalendar> calendars;
  final Set<String> hidden;
  final AgendaFilter filter;
  final String? eventCalendarId;

  @override
  State<AgendaCalendarPicker> createState() => _AgendaCalendarPickerState();
}

class _AgendaCalendarPickerState extends State<AgendaCalendarPicker> {
  late final Set<String> hidden = {...widget.hidden};
  late bool hideUnanswered = widget.filter.hideUnanswered;
  late bool hideHolidays = widget.filter.hideHolidays;
  late String? eventCalendarId = widget.eventCalendarId;
  late String? aiEventCalendarId = widget.aiEventCalendarId;
  late final List<String> words = [...widget.filter.hiddenWords];
  late final List<HiddenAgendaEvent> hiddenEvents = [
    ...widget.filter.hiddenEvents,
  ];
  late final Map<String, String>? colors = widget.colors == null
      ? null
      : {...widget.colors!};

  bool get hasFilters =>
      hidden.isNotEmpty ||
      hideHolidays ||
      hideUnanswered ||
      words.isNotEmpty ||
      hiddenEvents.isNotEmpty;

  String get filterSummary => [
    if (hidden.isNotEmpty) '${hidden.length} calendari nascosti',
    if (hideHolidays) 'festività nascoste',
    if (hideUnanswered) 'inviti senza risposta nascosti',
    if (words.isNotEmpty) '${words.length} filtri per parola',
    if (hiddenEvents.isNotEmpty) '${hiddenEvents.length} eventi/serie nascosti',
  ].join(' · ');

  void _clearFilters() => setState(() {
    hidden.clear();
    hideHolidays = false;
    hideUnanswered = false;
    words.clear();
    hiddenEvents.clear();
    wordInput.clear();
  });

  /// Google Calendar's event colours, with their Italian names.
  static const palette = [
    ('Pomodoro', '#D50000'),
    ('Fenicottero', '#E67C73'),
    ('Mandarino', '#F4511E'),
    ('Banana', '#F6BF26'),
    ('Salvia', '#33B679'),
    ('Basilico', '#0B8043'),
    ('Pavone', '#039BE5'),
    ('Mirtillo', '#3F51B5'),
    ('Lavanda', '#7986CB'),
    ('Uva', '#8E24AA'),
    ('Grafite', '#616161'),
  ];

  Future<void> _chooseColor(AgendaCalendar calendar) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Colore di ${calendar.name}'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (name, hex) in palette)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      key: ValueKey('agenda-color-$hex'),
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(dialogContext, hex),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: parseCalendarColor(hex),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SimpleDialogOption(
            key: const ValueKey('agenda-color-reset'),
            // Empty string: back to the calendar's own colour.
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Colore originale del calendario'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      picked.isEmpty
          ? colors!.remove(calendar.id)
          : colors![calendar.id] = picked;
    });
  }

  final wordInput = TextEditingController();

  @override
  void dispose() {
    wordInput.dispose();
    super.dispose();
  }

  void _addWord() {
    final word = wordInput.text.trim();
    if (word.isEmpty) return;
    setState(() {
      if (!words.any((w) => w.toLowerCase() == word.toLowerCase())) {
        words.add(word);
      }
      wordInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final writable = [
      for (final calendar in widget.calendars)
        if (calendar.writable) calendar,
    ];
    final rows = <Widget>[
      if (writable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('agenda-event-calendar-default'),
            initialValue: writable.any((c) => c.id == eventCalendarId)
                ? eventCalendarId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nuovi eventi in (+)'),
            items: [
              for (final calendar in writable)
                DropdownMenuItem(
                  value: calendar.id,
                  child: Text(
                    calendar.accountName.isEmpty ||
                            calendar.accountName == calendar.name
                        ? calendar.name
                        : '${calendar.name} · ${calendar.accountName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => eventCalendarId = value),
          ),
        ),
      if (writable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('agenda-ai-event-calendar'),
            initialValue: writable.any((c) => c.id == aiEventCalendarId)
                ? aiEventCalendarId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Eventi creati da ✨ in',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Come i nuovi eventi'),
              ),
              for (final calendar in writable)
                DropdownMenuItem<String?>(
                  value: calendar.id,
                  child: Text(
                    calendar.accountName.isEmpty ||
                            calendar.accountName == calendar.name
                        ? calendar.name
                        : '${calendar.name} · ${calendar.accountName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => aiEventCalendarId = value),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('Filtri', style: theme.textTheme.labelLarge),
      ),
      SwitchListTile(
        key: const ValueKey('agenda-hide-unanswered'),
        value: hideUnanswered,
        title: const Text('Nascondi inviti senza risposta'),
        subtitle: const Text(
          'Riunioni a cui non hai accettato né rifiutato, come i broadcast',
        ),
        onChanged: (value) => setState(() => hideUnanswered = value),
      ),
      SwitchListTile(
        key: const ValueKey('agenda-hide-holidays'),
        value: hideHolidays,
        title: const Text('Nascondi festività'),
        subtitle: const Text(
          'Calendari delle feste nazionali e religiose di ogni account',
        ),
        onChanged: (value) => setState(() => hideHolidays = value),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('agenda-hidden-word'),
                controller: wordInput,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addWord(),
                decoration: const InputDecoration(
                  labelText: 'Nascondi eventi che contengono…',
                  hintText: 'es. Live Broadcast',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aggiungi parola',
              onPressed: _addWord,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      if (words.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in words)
                InputChip(
                  label: Text(word),
                  onDeleted: () => setState(() => words.remove(word)),
                ),
            ],
          ),
        ),
      if (hiddenEvents.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Nascosti in Todo (${hiddenEvents.length})',
            key: const ValueKey('agenda-hidden-events'),
            style: theme.textTheme.labelLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            'Restano nei loro calendari; qui non compaiono.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final hidden in hiddenEvents.reversed)
          ListTile(
            dense: true,
            title: Text(
              hidden.title.isEmpty ? '(senza titolo)' : hidden.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              hidden.series
                  ? 'Tutti gli eventi con questo titolo'
                  : DateFormat(
                      hidden.allDay ? 'EEE d MMM yyyy' : 'EEE d MMM yyyy HH:mm',
                      'it',
                    ).format(hidden.start),
            ),
            trailing: TextButton(
              key: ValueKey('agenda-show-${hidden.key}'),
              onPressed: () => setState(() => hiddenEvents.remove(hidden)),
              child: const Text('Ripristina'),
            ),
          ),
      ],
      const Divider(height: 24),
      if (colors != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            'Tocca il pallino per scegliere il colore di un calendario.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
    String? account;
    for (final calendar in widget.calendars) {
      if (calendar.accountName != account) {
        account = calendar.accountName;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              account.isEmpty ? 'Sul telefono' : account,
              style: theme.textTheme.labelLarge,
            ),
          ),
        );
      }
      final holiday = hideHolidays && isHolidayCalendar(calendar);
      rows.add(
        SwitchListTile(
          // Held off by "Nascondi festività" while that is on.
          value: !holiday && !hidden.contains(calendar.id),
          subtitle: holiday ? const Text('Festività: nascosto') : null,
          // Tap the dot to choose a colour (build 221).
          secondary: InkWell(
            key: ValueKey('agenda-color-of-${calendar.id}'),
            customBorder: const CircleBorder(),
            onTap: colors == null ? null : () => _chooseColor(calendar),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                radius: 8,
                backgroundColor:
                    parseCalendarColor(
                      colors?[calendar.id] ?? calendar.colorHex,
                    ) ??
                    theme.colorScheme.primary,
              ),
            ),
          ),
          title: Text(calendar.name),
          onChanged: holiday
              ? null
              : (show) => setState(() {
                  show ? hidden.remove(calendar.id) : hidden.add(calendar.id);
                }),
        ),
      );
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Calendari e filtri',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (hasFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(filterSummary, style: theme.textTheme.bodySmall),
              ),
            Flexible(child: ListView(shrinkWrap: true, children: rows)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: hasFilters ? _clearFilters : null,
                    child: const Text('Azzera filtri'),
                  ),
                  FilledButton(
                    onPressed: () {
                      // A word typed but not yet added still counts.
                      _addWord();
                      Navigator.pop(
                        context,
                        AgendaPickerResult(
                          colors: colors,
                          hidden,
                          AgendaFilter(
                            hideUnanswered: hideUnanswered,
                            hiddenWords: List.unmodifiable(words),
                            hideHolidays: hideHolidays,
                            hiddenEvents: List.unmodifiable(hiddenEvents),
                          ),
                          eventCalendarId: eventCalendarId,
                          aiEventCalendarId: aiEventCalendarId,
                        ),
                      );
                    },
                    child: const Text('Applica'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
