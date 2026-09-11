import 'package:supabase_flutter/supabase_flutter.dart';

/// Keyset pages, including servers configured with a smaller response cap.
/// Never infer completion from a short page; only an empty page ends the scan.
Stream<List<Map<String, dynamic>>> remotePages(
  SupabaseClient client,
  String table, {
  int pageSize = 200,
}) async* {
  String? cursor;
  while (true) {
    var query = client.from(table).select();
    if (cursor != null) query = query.gt('id', cursor);
    final rows = await query.order('id').limit(pageSize);
    if (rows.isEmpty) return;
    final next = rows.last['id'] as String;
    if (cursor != null && next.compareTo(cursor) <= 0) {
      throw StateError('Remote pagination did not advance');
    }
    yield rows;
    cursor = next;
  }
}
