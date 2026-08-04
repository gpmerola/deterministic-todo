import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSupabaseStorage extends LocalStorage {
  const SecureSupabaseStorage({this.storage = const FlutterSecureStorage()});

  static const _sessionKey = 'supabase_persistent_session';
  final FlutterSecureStorage storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      await storage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => storage.read(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => storage.delete(key: _sessionKey);
}
