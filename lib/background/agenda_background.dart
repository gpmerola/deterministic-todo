import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../data/sync/secure_supabase_storage.dart';
import '../services/agenda_phone_sync.dart';
import '../services/agenda_service.dart';

/// Headless entry point (see `AgendaBackground.java`): runs only when the
/// app's own engine is not alive. Opens the same database and the stored
/// Supabase session, does one [AgendaPhoneSync.background] run and lets the
/// native side destroy the engine. No UI, no timers, nothing logged.
Future<void> startAgendaBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  AgendaPhoneSync.backgroundChannel.setMethodCallHandler((call) async {
    if (call.method != 'run') return null;
    return runAgendaBackground(call.arguments as String? ?? 'periodic');
  });
  await AgendaPhoneSync.backgroundChannel.invokeMethod<void>('ready');
}

Future<String> runAgendaBackground(String reason) async {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) return 'stop';
  final database = AppDatabase();
  try {
    final device = await (database.select(
      database.appSettings,
    )..where((setting) => setting.key.equals('device_id'))).getSingleOrNull();
    if (device == null) return 'stop';
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      postgrestOptions: const PostgrestClientOptions(
        requestTimeout: Duration(seconds: 20),
      ),
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSupabaseStorage(),
        // One run, then the engine is destroyed: no refresh timer, no links.
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    final sync = AgendaPhoneSync(
      service: AgendaService(database),
      client: Supabase.instance.client,
      deviceId: device.value,
    );
    return await sync.background(reason);
  } catch (_) {
    // Not logged: errors may carry event details.
    return 'retry';
  } finally {
    await database.close();
  }
}
