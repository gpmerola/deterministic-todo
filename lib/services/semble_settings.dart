import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/semble_availability.dart';
import '../domain/task.dart';

final class SembleConfig {
  const SembleConfig({
    required this.maskedKey,
    required this.userId,
    required this.enabled,
    this.doctorName,
    this.roomId,
  });

  /// Semble room of the user's availability (build 297): required by
  /// `createAvailability`; the key cannot read rooms, so it is typed in.
  final String? roomId;

  /// Surname as Semble writes it in `doctorName` (build 288): picks the
  /// user's bookings, since the key cannot read the clinician's id.
  final String? doctorName;

  /// "…a1b2" or null; the key itself never returns to the UI.
  final String? maskedKey;
  final String? userId;

  /// Whether the Calendar draws the layer.
  final bool enabled;

  bool get ready => maskedKey != null && userId != null;
}

CivilDate? _civil(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  return CivilDate(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
}

/// Key and Semble user id in the Android Keystore, like the assistant key:
/// never in SQLite, backups, logs or Supabase.
class SembleSettings {
  SembleSettings({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _apiKey = 'semble_api_key';
  static const _userId = 'semble_user_id';
  static const _enabled = 'semble_layer_enabled';
  static const _doctorName = 'semble_doctor_name';
  static const _roomId = 'semble_room_id';
  static const _rulesCache = 'semble_rules_cache';
  static const _conflictAlerts = 'semble_conflict_alerts';

  final FlutterSecureStorage _storage;

  static String mask(String key) =>
      key.length <= 4 ? '…' : '…${key.substring(key.length - 4)}';

  Future<SembleConfig> read() async {
    final key = await _storage.read(key: _apiKey);
    final user = await _storage.read(key: _userId);
    return SembleConfig(
      maskedKey: key == null || key.isEmpty ? null : mask(key),
      userId: user == null || user.isEmpty ? null : user,
      enabled: await _storage.read(key: _enabled) != 'false',
      doctorName: switch (await _storage.read(key: _doctorName)) {
        final name? when name.trim().isNotEmpty => name.trim(),
        _ => null,
      },
      roomId: switch (await _storage.read(key: _roomId)) {
        final room? when room.trim().isNotEmpty => room.trim(),
        _ => null,
      },
    );
  }

  Future<String?> apiKey() => _storage.read(key: _apiKey);

  Future<void> save({
    String? key,
    required String userId,
    String? doctorName,
    String? roomId,
  }) async {
    final trimmedUser = userId.trim();
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(trimmedUser)) {
      throw const FormatException('User ID non valido');
    }
    if (key != null) {
      final trimmed = key.trim();
      if (trimmed.isEmpty) throw const FormatException('Chiave vuota');
      await _storage.write(key: _apiKey, value: trimmed);
    }
    await _storage.write(key: _userId, value: trimmedUser);
    if (doctorName != null) {
      await _storage.write(key: _doctorName, value: doctorName.trim());
    }
    if (roomId != null) {
      final room = roomId.trim();
      if (room.isNotEmpty && !RegExp(r'^[A-Za-z0-9]+$').hasMatch(room)) {
        throw const FormatException('ID stanza non valido');
      }
      await _storage.write(key: _roomId, value: room);
    }
  }

  Future<void> setEnabled(bool enabled) =>
      _storage.write(key: _enabled, value: '$enabled');

  /// Notifications for events that fall in bookable time (build 304); on
  /// unless switched off.
  Future<bool> conflictAlerts() async =>
      await _storage.read(key: _conflictAlerts) != 'false';

  Future<void> setConflictAlerts(bool enabled) =>
      _storage.write(key: _conflictAlerts, value: '$enabled');

  /// Rules last read and their window, for the background conflict check:
  /// it never calls Semble (build 304). Dates and times only.
  Future<void> saveRules(
    List<SembleRule> rules,
    CivilDate first,
    CivilDate last,
  ) => _storage.write(
    key: _rulesCache,
    value: jsonEncode({
      'first': '$first',
      'last': '$last',
      'rules': [for (final rule in rules) rule.toJson()],
    }),
  );

  Future<({List<SembleRule> rules, CivilDate first, CivilDate last})?>
  cachedRules() async {
    try {
      final raw = await _storage.read(key: _rulesCache);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, Object?>;
      final first = _civil(json['first']);
      final last = _civil(json['last']);
      if (first == null || last == null) return null;
      return (
        rules: [
          for (final item in (json['rules'] as List<Object?>? ?? const []))
            if (item is Map<String, Object?>) ?SembleRule.fromJson(item),
        ],
        first: first,
        last: last,
      );
    } on Object {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _apiKey);
    await _storage.delete(key: _userId);
    await _storage.delete(key: _enabled);
    await _storage.delete(key: _doctorName);
    await _storage.delete(key: _roomId);
    await _storage.delete(key: _rulesCache);
    await _storage.delete(key: _conflictAlerts);
  }
}
