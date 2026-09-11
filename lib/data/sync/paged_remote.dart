import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_request_scope.dart';

/// Keyset pages, including servers configured with a smaller response cap.
/// Never infer completion from a short page; only an empty page ends the scan.
Stream<List<Map<String, dynamic>>> remotePages(
  SupabaseClient client,
  String table, {
  int pageSize = 500,
  String? idPrefix,
  SyncRequestScope? scope,
}) async* {
  final requests = scope ?? SyncRequestScope(client);
  String? cursor;
  while (true) {
    var query = client.from(table).select();
    if (idPrefix != null) {
      if (!RegExp(r'^[0-9a-f]{2}$').hasMatch(idPrefix)) {
        throw ArgumentError('Invalid UUID bucket');
      }
      query = query.gte('id', '${idPrefix}000000-0000-0000-0000-000000000000');
      final next = int.parse(idPrefix, radix: 16) + 1;
      if (next < 256) {
        final upper = next.toRadixString(16).padLeft(2, '0');
        query = query.lt('id', '${upper}000000-0000-0000-0000-000000000000');
      }
    }
    if (cursor != null) query = query.gt('id', cursor);
    final rows = await requests.send(query.order('id').limit(pageSize));
    if (rows.isEmpty) return;
    final next = rows.last['id'] as String;
    if (cursor != null && next.compareTo(cursor) <= 0) {
      throw StateError('Remote pagination did not advance');
    }
    yield rows;
    cursor = next;
  }
}
