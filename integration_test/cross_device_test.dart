import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Start tools/synthetic_sync_server.py, reverse tcp:8877, and create Cross Web
/// from test/validation_app.dart in an isolated localhost browser origin first.
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('browser to Android to browser, with native SQLite reopen', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('TODO_VALIDATION'), isTrue);
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      endsWith('.dev.validation'),
    );
    final client = SupabaseClient(
      'http://127.0.0.1:8877',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'synthetic-token',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 86400,
        'user': {
          'id': '00000000-0000-4000-8000-000000000001',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-09-11T00:00:00Z',
        },
      }),
    );
    var db = AppDatabase();
    final repo = TaskRepository(
      db,
      deviceId: '00000000-0000-4000-8000-000000000002',
    );
    final sync = SyncService(db, client);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20; attempt++) {
        await sync.sync();
        if (sync.latest.phase == SyncPhase.current) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(sync.latest.phase, SyncPhase.current, reason: sync.latest.error);
      final webTask = await (db.select(
        db.tasks,
      )..where((t) => t.title.equals('Cross Web'))).getSingle();
      expect(webTask.notes, contains('example.com'));
      await repo.updateDetails(
        webTask,
        title: webTask.title,
        notes: 'Nota Android https://example.com/documento',
        showDate: webTask.showDate,
      );
      final existing = await (db.select(
        db.tasks,
      )..where((t) => t.title.equals('Cross Android'))).getSingleOrNull();
      if (existing == null) {
        await repo.create('Cross Android', notes: 'Creata sul Galaxy');
      }
      await sync.sync();
      expect(await db.select(db.outboxEntries).get(), isEmpty);
      await sync.dispose();
      await db.close();
      db = AppDatabase();
      final persisted = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(webTask.id))).getSingle();
      expect(persisted.notes, 'Nota Android https://example.com/documento');
      expect(
        await (db.select(
          db.tasks,
        )..where((t) => t.title.equals('Cross Android'))).getSingleOrNull(),
        isNotNull,
      );
      await db.close();
      await client.dispose();
    });
  });
}
