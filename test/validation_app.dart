import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Separate package/origin only. Never compile this entry point into Todo Test.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TODO_VALIDATION')) {
    throw StateError('Validation flag required');
  }
  if (!kIsWeb &&
      !(await PackageInfo.fromPlatform()).packageName.endsWith(
        '.dev.validation',
      )) {
    throw StateError('Refusing to open an operational database');
  }
  final db = AppDatabase();
  final device = await (db.select(
    db.appSettings,
  )..where((r) => r.key.equals('device_id'))).getSingleOrNull();
  final deviceId = device?.value ?? const Uuid().v4();
  await db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: 'device_id', value: deviceId),
      );
  final repo = TaskRepository(db, deviceId: deviceId);
  const fixtureUrl = String.fromEnvironment('SYNC_FIXTURE_URL');
  SupabaseClient? client;
  SyncService? sync;
  if (fixtureUrl.isNotEmpty) {
    final uri = Uri.parse(fixtureUrl);
    if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
      throw StateError('Only a loopback fixture server is allowed');
    }
    client = SupabaseClient(
      fixtureUrl,
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
    sync = SyncService(db, client);
    // Explicit checks through the normal status button; no Realtime or polling.
    await sync.sync();
  }
  runApp(
    TodoApp(
      repository: repo,
      syncClient: client,
      syncService: sync,
      enablePlatformServices: false,
    ),
  );
}
