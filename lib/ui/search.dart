import 'package:flutter/material.dart';

import '../data/local/database.dart';
import '../data/task_repository.dart';
import '../domain/quick_add_parser.dart';
import '../domain/task.dart';
import 'app_section.dart';

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
  });
  final TaskRepository repository;
  final ValueChanged<AppSection> onNavigate;
  final Future<void> Function(String raw) onCreate;
  final Widget Function(Task task) tileBuilder;
  final Set<TaskSearchFilter> _filters = {};
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
                      showSuggestions(context);
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
              final results = snapshot.data ?? const <Task>[];
              return ListView(
                children: [
                  for (final task in results) tileBuilder(task),
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
