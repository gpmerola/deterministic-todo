import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/sync/sync_service.dart';
import '../../data/task_repository.dart';
import '../app_undo.dart';
import 'empty_view_label.dart';
import 'task_order.dart';

Color projectColor(String? value) => switch (value) {
  'red' || 'berry_red' => Colors.red,
  'orange' => Colors.orange,
  'yellow' => Colors.amber,
  'blue' || 'sky_blue' => Colors.blue,
  'purple' || 'violet' => Colors.purple,
  'pink' || 'magenta' => Colors.pink,
  'green' || 'lime_green' => Colors.green,
  _ => Colors.grey,
};

/// Project list, or the selected project's sections and items.
///
/// Selection is owned by the shell (back navigation and the SQL view depend
/// on it); [tasks] are the selected project's items from `watchView`.
class ProjectsView extends StatefulWidget {
  const ProjectsView({
    required this.repository,
    required this.tasks,
    required this.selectedProjectId,
    required this.onSelectProject,
    required this.beforeLeavingProject,
    required this.onAddTask,
    required this.tileBuilder,
    this.syncService,
    super.key,
  });

  final TaskRepository repository;
  final SyncService? syncService;
  final List<Task> tasks;
  final String? selectedProjectId;
  final ValueChanged<String?> onSelectProject;

  /// Lets the shell save an open desktop editor; false keeps the project.
  final Future<bool> Function() beforeLeavingProject;
  final void Function(String projectId, String? sectionId) onAddTask;
  final Widget Function(Task task) tileBuilder;

  @override
  State<ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<ProjectsView> {
  TaskRepository get repository => widget.repository;

  late final Stream<List<Project>> projectStream =
      (repository.db.select(repository.db.projects)..orderBy([
            (row) => OrderingTerm(expression: row.position),
            (row) => OrderingTerm(expression: row.name),
          ]))
          .watch();
  late final Stream<List<ProjectSection>> sectionStream = (repository.db.select(
    repository.db.projectSections,
  )..orderBy([(row) => OrderingTerm(expression: row.position)])).watch();

  Future<void> _sync() async => widget.syncService?.sync();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Project>>(
    stream: projectStream,
    builder: (context, projectSnapshot) => StreamBuilder<List<ProjectSection>>(
      stream: sectionStream,
      builder: (context, sectionSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final sections = sectionSnapshot.data ?? const <ProjectSection>[];
        final activeProjects = projects
            .where((item) => !item.isArchived)
            .toList();
        final selected = activeProjects
            .where((item) => item.id == widget.selectedProjectId)
            .firstOrNull;
        if (selected == null) return _projectIndex(activeProjects);
        final projectSections = sections
            .where((item) => item.projectId == selected.id && !item.isArchived)
            .toList();
        final projectTasks = List<Task>.of(widget.tasks)
          ..sort((a, b) => compareByPriority(a, b, ''));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('back-to-projects'),
                    tooltip: 'Tutti i progetti',
                    onPressed: () async {
                      if (await widget.beforeLeavingProject()) {
                        widget.onSelectProject(null);
                      }
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: projectColor(selected.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aggiungi sezione',
                    onPressed: () => _addSection(selected.id),
                    icon: const Icon(Icons.add_box_outlined),
                  ),
                  _projectActions(selected, activeProjects),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _projectList(selected.id, projectSections, projectTasks),
            ),
          ],
        );
      },
    ),
  );

  Widget _projectIndex(List<Project> activeProjects) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Text(
              'I miei progetti',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              key: const ValueKey('create-project'),
              tooltip: 'Nuovo progetto',
              onPressed: _addProject,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: activeProjects.isEmpty
            ? const EmptyViewLabel(
                'Nessun progetto',
                key: ValueKey('empty-projects'),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: activeProjects.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 48),
                itemBuilder: (context, index) {
                  final project = activeProjects[index];
                  return ListTile(
                    key: ValueKey('project-row-${project.id}'),
                    dense: true,
                    leading: Icon(
                      Icons.circle,
                      size: 12,
                      color: projectColor(project.color),
                    ),
                    title: Text(project.name),
                    trailing: _projectActions(project, activeProjects),
                    onTap: () => widget.onSelectProject(project.id),
                  );
                },
              ),
      ),
    ],
  );

  Widget _projectList(
    String projectId,
    List<ProjectSection> sections,
    List<Task> tasks,
  ) => ListView(
    key: PageStorageKey('project-list-$projectId'),
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      for (final section in sections)
        ExpansionTile(
          initiallyExpanded: true,
          title: Text(section.name),
          trailing: _sectionActions(section, sections),
          children: [
            for (final task in tasks.where(
              (item) => item.sectionId == section.id,
            ))
              widget.tileBuilder(task),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 20),
              title: const Text('Aggiungi'),
              onTap: () => widget.onAddTask(projectId, section.id),
            ),
          ],
        ),
      if (tasks.any((item) => item.sectionId == null))
        ExpansionTile(
          initiallyExpanded: true,
          title: const Text('Senza sezione'),
          children: [
            for (final task in tasks.where((item) => item.sectionId == null))
              widget.tileBuilder(task),
          ],
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.add, size: 20),
        title: const Text('Aggiungi'),
        onTap: () => widget.onAddTask(projectId, null),
      ),
    ],
  );

  Future<String?> _askName(
    String title,
    String label, {
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  Future<void> _addProject() async {
    final controller = TextEditingController();
    var color = 'green';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo progetto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in const [
                    'red',
                    'orange',
                    'yellow',
                    'green',
                    'blue',
                    'purple',
                    'pink',
                  ])
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: projectColor(value),
                      ),
                      label: const SizedBox.shrink(),
                      selected: color == value,
                      onSelected: (_) => setDialogState(() => color = value),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (controller.text, color)),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.trim().isEmpty) return;
    final id = await repository.createProject(result.$1, color: result.$2);
    if (mounted) widget.onSelectProject(id);
    await _sync();
  }

  Future<void> _addSection(String projectId) async {
    final name = await _askName('Nuova sezione', 'Nome');
    if (name == null) return;
    await repository.createProjectSection(projectId, name);
    await _sync();
  }

  Widget _projectActions(Project project, List<Project> projects) {
    final index = projects.indexWhere((item) => item.id == project.id);
    return PopupMenuButton<String>(
      key: ValueKey('project-actions-${project.id}'),
      tooltip: 'Azioni progetto',
      onSelected: (action) =>
          _handleProjectAction(action, project, projects, index),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
        PopupMenuItem(
          value: 'up',
          enabled: index > 0,
          child: const Text('Sposta su'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: index >= 0 && index < projects.length - 1,
          child: const Text('Sposta giù'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'inbox', child: Text('Sposta in Inbox')),
        const PopupMenuItem(value: 'delete', child: Text('Elimina')),
      ],
    );
  }

  Future<void> _handleProjectAction(
    String action,
    Project project,
    List<Project> projects,
    int index,
  ) async {
    if (action == 'rename') {
      final name = await _askName(
        'Rinomina progetto',
        'Nome',
        initialValue: project.name,
      );
      if (name == null) return;
      await repository.updateProject(project, name: name);
    } else if (action == 'up' && index > 0) {
      await repository.swapProjects(project, projects[index - 1]);
    } else if (action == 'down' && index < projects.length - 1) {
      await repository.swapProjects(project, projects[index + 1]);
    } else if (action == 'inbox') {
      if (!await _confirmMoveToInbox(project)) return;
      final moved = await repository.moveProjectToInbox(project);
      if (!mounted) return;
      if (widget.selectedProjectId == project.id) widget.onSelectProject(null);
      AppUndo.show(
        context,
        message: '${moved.length} attività spostate in Inbox',
        undo: () async {
          await repository.undoMoveProjectToInbox(project, moved);
          await _sync();
        },
      );
    } else if (action == 'delete') {
      await repository.updateProject(project, isArchived: true);
      if (!mounted) return;
      if (widget.selectedProjectId == project.id) widget.onSelectProject(null);
      AppUndo.show(
        context,
        message: 'Progetto “${project.name}” eliminato',
        undo: () async {
          final current = await (repository.db.select(
            repository.db.projects,
          )..where((row) => row.id.equals(project.id))).getSingle();
          await repository.updateProject(current, isArchived: false);
          await _sync();
        },
      );
    }
    await _sync();
  }

  Future<bool> _confirmMoveToInbox(Project project) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Spostare “${project.name}” in Inbox?'),
          content: const Text(
            'Le attività diventeranno senza progetto: quelle senza data '
            'compariranno in Oggi. Il progetto verrà archiviato; puoi '
            'annullare subito dopo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              key: const ValueKey('confirm-move-to-inbox'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sposta'),
            ),
          ],
        ),
      ) ??
      false;

  Widget _sectionActions(
    ProjectSection section,
    List<ProjectSection> sections,
  ) {
    final index = sections.indexWhere((item) => item.id == section.id);
    return PopupMenuButton<String>(
      key: ValueKey('section-actions-${section.id}'),
      tooltip: 'Azioni sezione',
      onSelected: (action) =>
          _handleSectionAction(action, section, sections, index),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rinomina')),
        PopupMenuItem(
          value: 'up',
          enabled: index > 0,
          child: const Text('Sposta su'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: index >= 0 && index < sections.length - 1,
          child: const Text('Sposta giù'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Elimina')),
      ],
    );
  }

  Future<void> _handleSectionAction(
    String action,
    ProjectSection section,
    List<ProjectSection> sections,
    int index,
  ) async {
    if (action == 'rename') {
      final name = await _askName(
        'Rinomina sezione',
        'Nome',
        initialValue: section.name,
      );
      if (name == null) return;
      await repository.updateProjectSection(section, name: name);
    } else if (action == 'up' && index > 0) {
      await repository.swapProjectSections(section, sections[index - 1]);
    } else if (action == 'down' && index < sections.length - 1) {
      await repository.swapProjectSections(section, sections[index + 1]);
    } else if (action == 'delete') {
      await repository.updateProjectSection(section, isArchived: true);
      if (!mounted) return;
      AppUndo.show(
        context,
        message: 'Sezione “${section.name}” eliminata',
        undo: () async {
          final current = await (repository.db.select(
            repository.db.projectSections,
          )..where((row) => row.id.equals(section.id))).getSingle();
          await repository.updateProjectSection(current, isArchived: false);
          await _sync();
        },
      );
    }
    await _sync();
  }
}
