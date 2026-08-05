part of '../main.dart';

class TrashView extends StatelessWidget {
  const TrashView({required this.repository, this.syncService, super.key});

  final TaskRepository repository;
  final SyncService? syncService;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.82,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Cestino',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Chiudi',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: repository.watchTrash(),
            builder: (context, taskSnapshot) => StreamBuilder<List<Project>>(
              stream: (repository.db.select(
                repository.db.projects,
              )..where((row) => row.isArchived.equals(true))).watch(),
              builder: (context, projectSnapshot) =>
                  StreamBuilder<List<ProjectSection>>(
                    stream: (repository.db.select(
                      repository.db.projectSections,
                    )..where((row) => row.isArchived.equals(true))).watch(),
                    builder: (context, sectionSnapshot) {
                      final tasks = taskSnapshot.data ?? const <Task>[];
                      final projects =
                          projectSnapshot.data ?? const <Project>[];
                      final sections =
                          sectionSnapshot.data ?? const <ProjectSection>[];
                      if (tasks.isEmpty &&
                          projects.isEmpty &&
                          sections.isEmpty) {
                        return const Center(child: Text('Cestino vuoto'));
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (tasks.isNotEmpty)
                            _trashHeader(context, 'Attività'),
                          for (final task in tasks)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_box_outlined),
                              title: TodoistLinkText(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Ripristina',
                                onPressed: () async {
                                  await repository.restore(task);
                                  await syncService?.sync();
                                },
                                icon: const Icon(Icons.restore),
                              ),
                            ),
                          if (projects.isNotEmpty)
                            _trashHeader(context, 'Progetti'),
                          for (final project in projects)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(project.name),
                              trailing: IconButton(
                                tooltip: 'Ripristina',
                                onPressed: () async {
                                  await repository.updateProject(
                                    project,
                                    isArchived: false,
                                  );
                                  await syncService?.sync();
                                },
                                icon: const Icon(Icons.restore),
                              ),
                            ),
                          if (sections.isNotEmpty)
                            _trashHeader(context, 'Sezioni'),
                          for (final section in sections)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.view_agenda_outlined),
                              title: Text(section.name),
                              trailing: IconButton(
                                tooltip: 'Ripristina',
                                onPressed: () async {
                                  await repository.updateProjectSection(
                                    section,
                                    isArchived: false,
                                  );
                                  await syncService?.sync();
                                },
                                icon: const Icon(Icons.restore),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _trashHeader(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}
