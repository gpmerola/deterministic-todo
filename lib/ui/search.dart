import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../data/local/database.dart';
import '../data/task_repository.dart';
import '../domain/agenda.dart';
import '../domain/quick_add_parser.dart';
import '../domain/task.dart';
import 'app_section.dart';
import 'event_search_controller.dart';

/// Universal command: search, `+` create, `>` open a view, `#` project.
///
/// Matching, ordering and the bound live in SQLite
/// ([TaskRepository.watchSearch]); one query per distinct input.
class TaskSearchDelegate extends SearchDelegate<void> {
  TaskSearchDelegate(
    this.repository, {
    required this.onNavigate,
    required this.onCreate,
    required this.tileBuilder,
    this.searchEvents,
    this.openEvent,
  });

  /// Android only: Agenda events matching the text, shown after the tasks.
  final Future<List<AgendaEntry>> Function(String text)? searchEvents;
  final Future<void> Function(BuildContext context, AgendaEntry entry)?
  openEvent;
  final TaskRepository repository;
  final ValueChanged<AppSection> onNavigate;
  final Future<void> Function(String raw) onCreate;
  final Widget Function(Task task) tileBuilder;
  final Set<TaskSearchFilter> _filters = {};
  final _revision = ValueNotifier(0);

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  String? _streamKey;
  Stream<List<Task>>? _stream;

  @override
  String get searchFieldLabel => 'Cerca, + crea, > apri, # progetto';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Stream<List<Task>> _search(String rawQuery) {
    final projectOnly = rawQuery.startsWith('#');
    final text = rawQuery.replaceFirst(RegExp(r'^[#]\s*'), '');
    final today = CivilDate.fromDateTime(DateTime.now()).toString();
    final key = [
      text,
      projectOnly,
      for (final filter in TaskSearchFilter.values) _filters.contains(filter),
      if (_filters.contains(TaskSearchFilter.today)) today,
    ].join('|');
    if (key != _streamKey) {
      _streamKey = key;
      _stream = repository.watchSearch(
        text: text,
        projectOnly: projectOnly,
        onDate: _filters.contains(TaskSearchFilter.today) ? today : null,
        undated: _filters.contains(TaskSearchFilter.undated),
        recurring: _filters.contains(TaskSearchFilter.recurring),
        highPriority: _filters.contains(TaskSearchFilter.highPriority),
      );
    }
    return _stream!;
  }

  Widget _results(BuildContext context) {
    final rawQuery = query.trim();
    if (rawQuery.startsWith('+')) return _createCommand(context, rawQuery);
    if (rawQuery.startsWith('>')) return _navigationCommand(context, rawQuery);
    return ValueListenableBuilder<int>(
      valueListenable: _revision,
      builder: (context, _, _) => _taskResults(context, rawQuery),
    );
  }

  Widget _taskResults(BuildContext context, String rawQuery) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              for (final filter in TaskSearchFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(filter.label),
                    selected: _filters.contains(filter),
                    onSelected: (selected) {
                      selected ? _filters.add(filter) : _filters.remove(filter);
                      _revision.value++;
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: _search(rawQuery),
            builder: (context, snapshot) {
              final waiting =
                  snapshot.connectionState == ConnectionState.waiting;
              // StreamBuilder retains the old snapshot when the query changes.
              // It must not appear to answer the new text or filters.
              final results = waiting || snapshot.hasError
                  ? const <Task>[]
                  : snapshot.data ?? const <Task>[];
              return ListView(
                children: [
                  if (waiting)
                    const LinearProgressIndicator()
                  else if (snapshot.hasError)
                    ListTile(
                      title: const Text('Ricerca attività non riuscita.'),
                      trailing: TextButton(
                        onPressed: () {
                          _streamKey = null;
                          _revision.value++;
                        },
                        child: const Text('Riprova'),
                      ),
                    )
                  else if (results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nessuna attività trovata.'),
                    ),
                  for (final task in results) tileBuilder(task),
                  if (searchEvents != null &&
                      _filters.isEmpty &&
                      !rawQuery.startsWith('#'))
                    _eventResults(context, rawQuery),
                  if (results.length >= TaskRepository.searchLimit)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Mostro i primi ${TaskRepository.searchLimit} '
                        'risultati: affina la ricerca',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _eventResults(BuildContext context, String text) => _EventResults(
    key: const ValueKey('event-search-results'),
    query: text,
    search: searchEvents!,
    open: openEvent,
  );

  Widget _createCommand(BuildContext context, String rawQuery) {
    final command = rawQuery.substring(1).trim();
    final parsed = command.isEmpty
        ? null
        : const QuickAddParser().parse(command);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          enabled: parsed != null && parsed.title.isNotEmpty,
          leading: const Icon(Icons.add_circle_outline),
          title: Text(parsed?.title ?? 'Scrivi una nuova attività'),
          subtitle: parsed?.showDate == null
              ? null
              : Text(parsed!.showDate.toString()),
          onTap: parsed == null
              ? null
              : () async {
                  await onCreate(command);
                  if (context.mounted) close(context, null);
                },
        ),
      ],
    );
  }

  Widget _navigationCommand(BuildContext context, String rawQuery) {
    final needle = rawQuery.substring(1).trim().toLowerCase();
    final destinations = <AppSection>[
      AppSection.today,
      AppSection.upcoming,
      AppSection.projects,
      AppSection.completed,
      AppSection.settings,
    ].where((item) => item.label.toLowerCase().contains(needle));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final destination in destinations)
          ListTile(
            leading: Icon(destination.icon),
            title: Text(destination.label),
            onTap: () {
              close(context, null);
              onNavigate(destination);
            },
          ),
      ],
    );
  }
}

enum TaskSearchFilter {
  today('Oggi'),
  undated('Senza data'),
  recurring('Ricorrenti'),
  highPriority('Priorità alta');

  const TaskSearchFilter(this.label);
  final String label;
}

class _EventResults extends StatefulWidget {
  const _EventResults({
    required this.query,
    required this.search,
    this.open,
    super.key,
  });
  final String query;
  final Future<List<AgendaEntry>> Function(String) search;
  final Future<void> Function(BuildContext, AgendaEntry)? open;
  @override
  State<_EventResults> createState() => _EventResultsState();
}

class _EventResultsState extends State<_EventResults>
    with WidgetsBindingObserver {
  late final controller = EventSearchController(widget.search);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.setQuery(widget.query);
  }

  @override
  void didUpdateWidget(covariant _EventResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.setQuery(widget.query);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.invalidate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.failed) {
        return ListTile(
          title: const Text('Ricerca eventi non disponibile'),
          trailing: TextButton(
            onPressed: controller.invalidate,
            child: const Text('Riprova'),
          ),
        );
      }
      final events = controller.results;
      if (events.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final day = DateFormat('EEE d MMM yyyy', 'it');
      final clock = DateFormat.Hm('it');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Eventi',
              key: const ValueKey('search-events-header'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final event in events)
            ListTile(
              key: ValueKey('search-event-${event.instanceId}'),
              leading: const Icon(Icons.event_outlined),
              title: Text(event.title.isEmpty ? '(senza titolo)' : event.title),
              subtitle: Text(
                event.allDay
                    ? day.format(event.start)
                    : '${day.format(event.start)} · ${clock.format(event.start)}',
              ),
              onTap: () async {
                await widget.open?.call(context, event);
                if (mounted) controller.invalidate();
              },
            ),
        ],
      );
    },
  );
}
