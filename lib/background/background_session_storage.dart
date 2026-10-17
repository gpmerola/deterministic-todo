import 'package:supabase_flutter/supabase_flutter.dart';

/// Session storage for the short-lived background engine.
///
/// Reads and writes the same stored session as the app, but never deletes
/// it. Build 213–216 started this engine with token refresh disabled; with
/// an expired session gotrue then signed out locally and supabase_flutter
/// deleted the stored session, logging the user out of the phone (real
/// report, 4 October 2026). Only the visible app may end a session.
class BackgroundSessionStorage extends LocalStorage {
  const BackgroundSessionStorage(this.inner);

  final LocalStorage inner;

  @override
  Future<void> initialize() => inner.initialize();

  @override
  Future<bool> hasAccessToken() => inner.hasAccessToken();

  @override
  Future<String?> accessToken() => inner.accessToken();

  @override
  Future<void> persistSession(String persistSessionString) =>
      inner.persistSession(persistSessionString);

  /// Never: a refused refresh or an expired token in the background must
  /// leave the session to the app, which signs out only for real.
  @override
  Future<void> removePersistedSession() async {}
}

/// Auth options of the background engine: refresh allowed (an expired
/// session is refreshed, never signed out), no deep links, storage that
/// cannot delete the session.
FlutterAuthClientOptions backgroundAuthOptions(LocalStorage storage) =>
    FlutterAuthClientOptions(
      localStorage: BackgroundSessionStorage(storage),
      autoRefreshToken: true,
      detectSessionInUri: false,
    );
