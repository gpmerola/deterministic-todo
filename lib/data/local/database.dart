import 'package:drift/drift.dart';

import '../../services/platform_runtime_native.dart'
    if (dart.library.js_interop) '../../services/platform_runtime_web.dart';
import 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart';

part 'database.g.dart';

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get title => text().withLength(min: 1)();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text()();
  TextColumn get showDate => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  IntColumn get timeMinutes => integer().nullable()();
  TextColumn get timeZone => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get projectId => text().nullable()();
  TextColumn get sectionId => text().nullable()();
  TextColumn get externalSource => text().nullable()();
  TextColumn get externalId => text().nullable()();
  IntColumn get position => integer()();
  TextColumn get recurrence => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  TextColumn get occurrenceKey => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get logicalVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {seriesId, occurrenceKey},
  ];
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get color => text().nullable()();
  TextColumn get parentId => text().nullable()();
  IntColumn get position => integer()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get externalSource => text().nullable()();
  TextColumn get externalId => text().nullable()();
  IntColumn get logicalVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProjectSections extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get projectId => text()();
  TextColumn get name => text().withLength(min: 1)();
  IntColumn get position => integer()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get externalSource => text().nullable()();
  TextColumn get externalId => text().nullable()();
  IntColumn get logicalVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class OutboxEntries extends Table {
  TextColumn get operationId => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Tasks, Projects, ProjectSections, OutboxEntries, AppSettings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createPerformanceIndexes();
      await _createImportIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await _createPerformanceIndexes();
      if (from < 4) await _ensureImportSchema(migrator);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (!isWebPlatform) await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<void> _ensureImportSchema(Migrator migrator) async {
    for (final column in [
      tasks.priority,
      tasks.projectId,
      tasks.sectionId,
      tasks.externalSource,
      tasks.externalId,
    ]) {
      if (!await _columnExists('tasks', column.$name)) {
        await migrator.addColumn(tasks, column);
      }
    }
    if (!await _tableExists('projects')) await migrator.createTable(projects);
    if (!await _tableExists('project_sections')) {
      await migrator.createTable(projectSections);
    }
    await _createImportIndexes();
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<bool> _tableExists(String table) async {
    final row = await customSelect(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      variables: [Variable.withString('table'), Variable.withString(table)],
    ).getSingleOrNull();
    return row != null;
  }

  Future<void> _createPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tasks_status_order_idx '
      'ON tasks (deleted_at, status, position, created_at, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tasks_dates_idx '
      'ON tasks (deleted_at, show_date, due_date)',
    );
  }

  Future<void> _createImportIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS tasks_external_idx '
      'ON tasks (external_source, external_id) WHERE external_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS projects_external_idx '
      'ON projects (external_source, external_id) WHERE external_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS sections_external_idx '
      'ON project_sections (external_source, external_id) WHERE external_id IS NOT NULL',
    );
  }
}

QueryExecutor _openConnection() => openDatabaseConnection();
