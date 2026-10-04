import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// LLM providers the user can configure. No feature uses them yet: this only
/// stores and checks a key so later features can ask before sending data.
enum AiProvider {
  deepseek(
    label: 'DeepSeek',
    keyHint: 'sk-…',
    modelsUrl: 'https://api.deepseek.com/models',
  ),
  anthropic(
    label: 'Anthropic (Claude)',
    keyHint: 'sk-ant-…',
    modelsUrl: 'https://api.anthropic.com/v1/models',
  );

  const AiProvider({
    required this.label,
    required this.keyHint,
    required this.modelsUrl,
  });

  final String label;
  final String keyHint;

  /// Read-only listing used to check a key: it sends no user content.
  final String modelsUrl;

  Map<String, String> headers(String key) => switch (this) {
    AiProvider.deepseek => {'Authorization': 'Bearer $key'},
    AiProvider.anthropic => {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
    },
  };
}

final class AiConfig {
  const AiConfig({required this.provider, required this.maskedKey});

  final AiProvider provider;

  /// "…a1b2" or null when no key is stored. The key itself never reaches
  /// the UI after saving.
  final String? maskedKey;
  bool get hasKey => maskedKey != null;
}

enum AiKeyCheck { valid, rejected, unreachable }

/// API key storage in the platform keystore (Android Keystore through
/// flutter_secure_storage). Never written to SQLite, backups, logs or
/// Supabase; removed with [clear].
class AiSettings {
  AiSettings({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client; // ignore: prefer_initializing_formals

  static const _providerKey = 'ai_provider';
  static const _apiKey = 'ai_api_key';
  static const checkTimeout = Duration(seconds: 10);

  final FlutterSecureStorage _storage;
  final http.Client? _client;

  static String mask(String key) =>
      key.length <= 4 ? '…' : '…${key.substring(key.length - 4)}';

  Future<AiConfig> read() async {
    final providerName = await _storage.read(key: _providerKey);
    final key = await _storage.read(key: _apiKey);
    return AiConfig(
      provider: AiProvider.values.firstWhere(
        (provider) => provider.name == providerName,
        orElse: () => AiProvider.deepseek,
      ),
      maskedKey: key == null || key.isEmpty ? null : mask(key),
    );
  }

  /// The stored key, for a future explicit request only.
  Future<String?> apiKey() => _storage.read(key: _apiKey);

  Future<void> save(AiProvider provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) throw const FormatException('Chiave vuota');
    await _storage.write(key: _providerKey, value: provider.name);
    await _storage.write(key: _apiKey, value: trimmed);
  }

  Future<void> clear() async {
    await _storage.delete(key: _apiKey);
    await _storage.delete(key: _providerKey);
  }

  /// One GET of the provider's model list with the key: no prompt, task or
  /// event is sent. Errors are not logged (the key is in the headers).
  Future<AiKeyCheck> check(AiProvider provider, String key) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(provider.modelsUrl), headers: provider.headers(key))
          .timeout(checkTimeout);
      if (response.statusCode == 200) return AiKeyCheck.valid;
      if (response.statusCode == 401 || response.statusCode == 403) {
        return AiKeyCheck.rejected;
      }
      return AiKeyCheck.unreachable;
    } on Object {
      return AiKeyCheck.unreachable;
    } finally {
      if (_client == null) client.close();
    }
  }
}
