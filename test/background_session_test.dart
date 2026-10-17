import 'package:deterministic_todo/background/background_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryStorage extends LocalStorage {
  String? value = '{"stored":true}';
  int removals = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => value != null;

  @override
  Future<String?> accessToken() async => value;

  @override
  Future<void> persistSession(String persistSessionString) async =>
      value = persistSessionString;

  @override
  Future<void> removePersistedSession() async {
    removals++;
    value = null;
  }
}

void main() {
  // Regression (4 October 2026): the background engine logged the user out
  // of the phone by deleting the stored session after a local sign-out.
  test('the background engine can never delete the stored session', () async {
    final inner = _MemoryStorage();
    final storage = BackgroundSessionStorage(inner);
    await storage.removePersistedSession();
    expect(inner.removals, 0);
    expect(await storage.accessToken(), '{"stored":true}');
    await storage.persistSession('{"refreshed":true}');
    expect(inner.value, '{"refreshed":true}');
    expect(await storage.hasAccessToken(), isTrue);
  });

  test('background auth refreshes instead of signing out', () {
    final options = backgroundAuthOptions(_MemoryStorage());
    // With refresh disabled gotrue signs out on an expired session.
    expect(options.autoRefreshToken, isTrue);
    expect(options.detectSessionInUri, isFalse);
    expect(options.localStorage, isA<BackgroundSessionStorage>());
  });
}
