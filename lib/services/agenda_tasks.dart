import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';
import '../domain/task.dart';

/// "Mostra in agenda" flags for Todo tasks. Kept only on this phone (the
/// Agenda is Android-only) in `app_settings`, so the synced task schema and
/// Supabase stay unchanged; backups carry it with the other settings. A task
/// of a recurring series is flagged by series, so every occurrence follows.
class AgendaTaskLinks {
  AgendaTaskLinks(this._database);

  static const key = 'agenda_task_links';
  final AppDatabase _database;

  static String _keyFor(Task task) =>
      task.seriesId != null ? 'series:${task.seriesId}' : 'task:${task.id}';

  Future<Set<String>> _keys() async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
    if (row == null) return {};
    try {
      return {
        for (final value in jsonDecode(row.value) as List) value as String,
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<bool> isShown(Task task) async =>
      (await _keys()).contains(_keyFor(task));

  Future<void> setShown(Task task, bool shown) async {
    final keys = await _keys();
    shown ? keys.add(_keyFor(task)) : keys.remove(_keyFor(task));
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: jsonEncode(keys.toList()..sort()),
          ),
        );
  }

  /// Flagged, not deleted tasks dated in [first, first + days), completed
  /// ones included (shown struck through).
  Future<List<AgendaTaskItem>> tasksBetween(CivilDate first, int days) async {
    final keys = await _keys();
    if (keys.isEmpty) return const [];
    final ids = [
      for (final k in keys)
        if (k.startsWith('task:')) k.substring(5),
    ];
    final series = [
      for (final k in keys)
        if (k.startsWith('series:')) k.substring(7),
    ];
    final last = first.addDays(days - 1).toString();
    final rows =
        await (_database.select(_database.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.showDate.isBiggerOrEqualValue(first.toString()) &
                  t.showDate.isSmallerOrEqualValue(last) &
                  (t.id.isIn(ids) | t.seriesId.isIn(series)),
            ))
            .get();
    return [
      for (final row in rows)
        AgendaTaskItem(
          id: row.id,
          title: row.title,
          date: CivilDate.parse(row.showDate!),
          completed: row.completedAt != null,
        ),
    ];
  }
}
