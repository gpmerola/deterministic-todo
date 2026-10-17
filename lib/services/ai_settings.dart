import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// LLM providers the user can configure. Used only by explicit actions
/// (the assistant capture), never in the background.
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

enum AiFailure { noKey, rejected, unreachable, badResponse, truncated }

class AiException implements Exception {
  const AiException(this.failure);
  final AiFailure failure;

  String get message => switch (failure) {
    AiFailure.noKey =>
      'Configura la chiave API in Impostazioni → Assistente AI.',
    AiFailure.rejected => 'Il fornitore ha rifiutato la chiave API.',
    AiFailure.unreachable =>
      'Servizio AI non raggiungibile: controlla la rete e riprova.',
    AiFailure.badResponse =>
      'Risposta dell\'AI non comprensibile: riprova o riformula.',
    AiFailure.truncated =>
      'Risposta troppo lunga e interrotta: dividi la nota in parti più brevi.',
  };
}

/// One explicit request to the configured provider. Prompts and replies are
/// never logged or stored; the caller shows the result for confirmation.
String? _deepseekText(Map<String, Object?> decoded) {
  final choice = (decoded['choices'] as List).first as Map<String, Object?>;
  if (choice['finish_reason'] == 'length') {
    throw const AiException(AiFailure.truncated);
  }
  final message = choice['message'] as Map<String, Object?>;
  return message['content'] as String?;
}

class AiClient {
  AiClient(this.settings, {http.Client? client})
    : _client = client; // ignore: prefer_initializing_formals

  final AiSettings settings;
  final http.Client? _client;

  static const deepseekModel = 'deepseek-flash';
  static const claudeModel = 'claude-haiku-4-5';
  static const timeout = Duration(seconds: 45);

  Future<String> completeJson({
    required String system,
    required String user,
  }) async {
    final key = await settings.apiKey();
    if (key == null || key.isEmpty) throw const AiException(AiFailure.noKey);
    final provider = (await settings.read()).provider;
    final client = _client ?? http.Client();
    try {
      final http.Response response;
      switch (provider) {
        case AiProvider.deepseek:
          response = await client
              .post(
                Uri.parse('https://api.deepseek.com/chat/completions'),
                headers: {
                  ...provider.headers(key),
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': deepseekModel,
                  'messages': [
                    {'role': 'system', 'content': system},
                    {'role': 'user', 'content': user},
                  ],
                  'response_format': {'type': 'json_object'},
                  // Thinking is on by default for deepseek-flash and its
                  // reasoning ran out of tokens on two-item notes (build
                  // 206), truncating the json. Off: faster and cheaper.
                  'thinking': {'type': 'disabled'},
                  'max_tokens': 4096,
                  'stream': false,
                }),
              )
              .timeout(timeout);
        case AiProvider.anthropic:
          response = await client
              .post(
                Uri.parse('https://api.anthropic.com/v1/messages'),
                headers: {
                  ...provider.headers(key),
                  'content-type': 'application/json',
                },
                body: jsonEncode({
                  'model': claudeModel,
                  'max_tokens': 4096,
                  'system': system,
                  'messages': [
                    {'role': 'user', 'content': user},
                  ],
                }),
              )
              .timeout(timeout);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiException(AiFailure.rejected);
      }
      if (response.statusCode != 200) {
        throw const AiException(AiFailure.unreachable);
      }
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      final text = switch (provider) {
        AiProvider.deepseek => _deepseekText(decoded),
        AiProvider.anthropic when decoded['stop_reason'] == 'max_tokens' =>
          throw const AiException(AiFailure.truncated),
        AiProvider.anthropic => [
          for (final block in decoded['content'] as List)
            if ((block as Map)['type'] == 'text') block['text'] as String,
        ].join(),
      };
      if (text == null || text.trim().isEmpty) {
        throw const AiException(AiFailure.badResponse);
      }
      return text;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(AiFailure.unreachable);
    } on http.ClientException {
      throw const AiException(AiFailure.unreachable);
    } on Object {
      throw const AiException(AiFailure.badResponse);
    } finally {
      if (_client == null) client.close();
    }
  }
}
