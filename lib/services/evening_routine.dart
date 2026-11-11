import 'package:drift/drift.dart';

import '../data/local/database.dart';

/// Device-local presentation choice. One setting per series avoids rewriting
/// unrelated flags; ordinary JSON backups carry these portable settings.
class EveningRoutine {
  EveningRoutine(this.db);

  static const prefix = 'evening_routine:';
  final AppDatabase db;

  static String identity(Task task) => task.seriesId ?? task.id;

  Stream<Set<String>> watch() =>
      (db.select(db.appSettings)..where(
            (row) => row.key.like('evening!_routine:%', escapeChar: '!'),
          ))
          .watch()
          .map(
            (rows) => {
              for (final row in rows)
                if (row.value == '1') row.key.substring(prefix.length),
            },
          );

  Future<void> setEnabled(Task task, bool enabled) => db.transaction(() async {
    final key = '$prefix${identity(task)}';
    if (enabled) {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: '1'),
          );
    } else {
      await (db.delete(
        db.appSettings,
      )..where((row) => row.key.equals(key))).go();
    }
  });
}
