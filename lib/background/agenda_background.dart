import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../data/sync/secure_supabase_storage.dart';
import '../services/agenda_phone_sync.dart';
import '../services/agenda_service.dart';
import 'background_session_storage.dart';

/// Headless entry point (see `AgendaBackground.java`): runs only when the
/// app's own engine is not alive. Opens the same database and the stored
/// Supabase session, does one [AgendaPhoneSync.background] run and lets the
/// native side destroy the engine. It may refresh an expired session (and
/// saves the result) but can never delete it: see
/// [BackgroundSessionStorage]. No UI, nothing logged.
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
  const stored = SecureSupabaseStorage();
  // Not signed in on this phone: nothing to do until the app signs in.
  if (await stored.accessToken() == null) return 'stop';
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
      authOptions: backgroundAuthOptions(stored),
    );
    final client = Supabase.instance.client;
    // initialize() recovers the stored session without waiting for it.
    final session = await _recoveredSession(client);
    // Expired and not refreshable now (offline): try again later; the
    // stored session is left untouched for the app.
    if (session == null) return 'retry';
    final sync = AgendaPhoneSync(
      service: AgendaService(database),
      client: client,
      deviceId: device.value,
    );
    final result = await sync.background(reason);
    // A refresh made here must be on disk before the engine is destroyed,
    // or the app would later reuse a rotated refresh token.
    final current = client.auth.currentSession;
    if (current != null) {
      await stored.persistSession(jsonEncode(current.toJson()));
    }
    return result;
  } catch (_) {
    // Not logged: errors may carry event details.
    return 'retry';
  } finally {
    await database.close();
  }
}

Future<Session?> _recoveredSession(SupabaseClient client) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline)) {
    final session = client.auth.currentSession;
    if (session != null && !session.isExpired) return session;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return null;
}
