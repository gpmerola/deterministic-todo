import '../data/local/database.dart';
import '../data/task_repository.dart';
import '../domain/link_syntax.dart';
import '../domain/quick_add_metadata.dart';
import '../domain/task_planning.dart';

/// Text and choices of one quick-add submission.
typedef QuickAddInput = ({
  String text,
  String notes,
  int priority,
  String? projectId,
  String? sectionId,
});

/// Owns quick-add persistence and its next-opening cache; never owns UI state.
class QuickAddService {
  QuickAddService(this.repository);
  final TaskRepository repository;
  List<Project> projects = const [];
  String? lastProjectId;

  Future<void> refresh() async {
    final db = repository.db;
    final all = await db.select(db.projects).get();
    final settings = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('last_quick_project'))).get();
    projects = all.where((item) => !item.isArchived).toList();
    lastProjectId = settings.firstOrNull?.value;
  }

  Future<void> create(
    QuickAddInput input, {
    required List<Project> projects,
  }) async {
    final metadata = parseQuickAddMetadata(
      input.text,
      defaultPriority: input.priority,
      defaultProjectId: input.projectId,
      projectsByName: {
        for (final project in projects.where((item) => !item.isArchived))
          project.name: project.id,
      },
    );
    final parsed = parsePlannedQuickTask(metadata.text);
    final notes = input.notes.trim();
    await repository.create(
      linkifyPlainUrls(parsed.title),
      showDate: parsed.showDate!.toString(),
      notes: notes.isEmpty ? null : linkifyPlainUrls(notes),
      recurrence: parsed.recurrence,
      priority: metadata.priority,
      projectId: metadata.projectId,
      sectionId: metadata.projectId == input.projectId ? input.sectionId : null,
    );
    await repository.db
        .into(repository.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'last_quick_project',
            value: metadata.projectId ?? '',
          ),
        );
    lastProjectId = metadata.projectId;
  }
}
