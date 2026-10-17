part of 'database.dart';

Future<void> _installFingerprintCache(AppDatabase db) async {
  // Cache invalidation is part of the row transaction, including imports,
  // remote merges, physical deletes and rollbacks from every SQLite writer.
  for (final operation in ['insert', 'update', 'delete']) {
    final keys = <String>[
      if (operation != 'insert') "'sync_fp:v1:tasks:' || substr(OLD.id, 1, 2)",
      if (operation != 'delete') "'sync_fp:v1:tasks:' || substr(NEW.id, 1, 2)",
    ];
    await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tasks_fingerprint_$operation AFTER $operation ON tasks
      BEGIN
        DELETE FROM app_settings WHERE key IN (${keys.join(',')});
      END
    ''');
  }
}
