import 'dart:convert';

import 'local/database.dart';

/// Private local drafts. Never included in the sync outbox or backup exports.
class EditorDrafts {
  EditorDrafts(this.db);
  final AppDatabase db;

  Future<Map<String, dynamic>?> read(String id) async {
    final row = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals('editor_draft:$id'))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.value) as Map<String, dynamic>;
  }

  Future<void> write(String id, Map<String, dynamic> value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'editor_draft:$id',
          value: jsonEncode(value),
        ),
      );

  Future<void> remove(String id) => (db.delete(
    db.appSettings,
  )..where((r) => r.key.equals('editor_draft:$id'))).go();
}
