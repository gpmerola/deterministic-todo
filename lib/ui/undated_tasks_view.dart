part of '../main.dart';

class UndatedTasksView extends StatelessWidget {
  const UndatedTasksView({
    required this.repository,
    this.syncService,
    super.key,
  });

  final TaskRepository repository;
  final SyncService? syncService;

  Future<void> _delete(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rimuovere questa attività?'),
        content: const Text(
          'L’attività senza data sarà rimossa da tutti i dispositivi dopo la '
          'sincronizzazione. Potrai ancora recuperarla dal Cestino.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.softDelete(task);
    await syncService?.sync();
  }

  Future<void> _deleteAll(BuildContext context, List<Task> tasks) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rimuovere ${tasks.length} attività?'),
        content: const Text(
          'Tutte le attività attive senza data saranno rimosse e '
          'sincronizzate. Potrai ancora recuperarle dal Cestino.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rimuovi tutte'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final task in tasks) {
      await repository.softDelete(task);
    }
    await syncService?.sync();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.82,
    child: StreamBuilder<List<Task>>(
      stream: repository.watchUndatedActive(),
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? const <Task>[];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Attività senza data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (tasks.isNotEmpty)
                    TextButton(
                      onPressed: () => _deleteAll(context, tasks),
                      child: const Text('Rimuovi tutte'),
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
              child: tasks.isEmpty
                  ? const Center(child: Text('Nessuna attività senza data'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return ListTile(
                          leading: const Icon(Icons.inbox_outlined),
                          title: TodoistLinkText(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            task.status == TaskStatus.waiting.name
                                ? 'In attesa'
                                : 'Inbox',
                          ),
                          trailing: IconButton(
                            tooltip: 'Rimuovi attività senza data',
                            onPressed: () => _delete(context, task),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
