import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/task.dart' show LogicalVersion;
import '../local/database.dart';

/// Drops notifications whose announced version this device already has,
/// such as the echo of its own accepted upload. Anything uncertain is fetched.
Future<Set<String>> realtimeIdsToFetch(
  AppDatabase db,
  String table,
  Set<String> ids,
  Map<String, LogicalVersion?> announced,
) async {
  if (!const {'tasks', 'projects', 'project_sections'}.contains(table)) {
    throw ArgumentError('Invalid sync table');
  }
  final known = ids.where((id) => announced[id] != null).toList();
  if (known.isEmpty) return ids;
  final rows = await db
      .customSelect(
        'SELECT id, logical_version, device_id FROM "$table" '
        'WHERE id IN (SELECT value FROM json_each(?))',
        variables: [Variable(jsonEncode(known))],
      )
      .get();
  final current = {
    for (final row in rows)
      row.read<String>('id'): LogicalVersion(
        row.read<int>('logical_version'),
        row.read<String>('device_id'),
      ),
  };
  return {
    for (final id in ids)
      if (announced[id] == null ||
          current[id] == null ||
          current[id]!.compareTo(announced[id]!) < 0)
        id,
  };
}
