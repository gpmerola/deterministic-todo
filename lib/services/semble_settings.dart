import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/semble_availability.dart';
import '../domain/semble_ical.dart';
import '../domain/semble_time.dart';
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
  static const _ignoredOverlaps = 'semble_ignored_overlaps';
  static const _icalLink = 'semble_ical_link';
  static const _bookingsCache = 'semble_bookings_cache';
  static const _todoBlocks = 'semble_todo_blocks';

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

  /// Occurrences whose amber edge the user removed (build 307):
  /// [sembleOverlapKey] to the end instant; finished ones drop out.
  Future<Map<String, int>> ignoredOverlaps({DateTime? now}) async {
    try {
      final raw = await _storage.read(key: _ignoredOverlaps);
      if (raw == null) return {};
      final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, Object?>).entries)
          if (value is int && value > at) key: value,
      };
    } on Object {
      return {};
    }
  }

  Future<void> saveIgnoredOverlaps(Map<String, int> ignored) =>
      _storage.write(key: _ignoredOverlaps, value: jsonEncode(ignored));

  /// Rules last read and their window, for the background conflict check:
  /// it never calls Semble (build 304). Dates and times only. From build
  /// 312 also the Calendar's fallback when Semble cannot be read, with the
  /// moment of the read ([savedAt]).
  Future<void> saveRules(
    List<SembleRule> rules,
    CivilDate first,
    CivilDate last, {
    DateTime? savedAt,
  }) => _storage.write(
    key: _rulesCache,
    value: jsonEncode({
      'first': '$first',
      'last': '$last',
      'savedAt': ?savedAt?.toUtc().toIso8601String(),
      'rules': [for (final rule in rules) rule.toJson()],
    }),
  );

  Future<
    ({
      List<SembleRule> rules,
      CivilDate first,
      CivilDate last,
      DateTime? savedAt,
    })?
  >
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
        savedAt: switch (json['savedAt']) {
          final String at => DateTime.tryParse(at)?.toLocal(),
          _ => null,
        },
      );
    } on Object {
      return null;
    }
  }

  /// The user's Semble iCal link (build 312): read without the API key
  /// when the key is missing or refused. Kept in the Keystore like the key,
  /// since anyone with it can read the visits.
  Future<String?> icalLink() async {
    final link = await _storage.read(key: _icalLink);
    return link == null || link.trim().isEmpty ? null : link.trim();
  }

  Future<void> saveIcalLink(String link) {
    final trimmed = link.trim();
    if (sembleIcalUri(trimmed) == null) {
      throw const FormatException('Link iCal non valido');
    }
    return _storage.write(key: _icalLink, value: trimmed);
  }

  Future<void> deleteIcalLink() => _storage.delete(key: _icalLink);

  /// Build 312 saved the last bookings; build 313 shows the Google copy
  /// instead and drops them.
  Future<void> deleteSavedBookings() => _storage.delete(key: _bookingsCache);

  Future<void> clear() async {
    await _storage.delete(key: _apiKey);
    await _storage.delete(key: _userId);
    await _storage.delete(key: _enabled);
    await _storage.delete(key: _doctorName);
    await _storage.delete(key: _roomId);
    await _storage.delete(key: _rulesCache);
    await _storage.delete(key: _conflictAlerts);
    await _storage.delete(key: _ignoredOverlaps);
    await _storage.delete(key: _todoBlocks);
    // The iCal link stays: it is the fallback without a key (build 312).
    await deleteSavedBookings();
  }

  /// Blocks created from Todo (build 317), so they can be removed later and
  /// not only by the snackbar's «Annulla». Id, day and London times only.
  Future<List<SembleTodoBlock>> todoBlocks() async {
    try {
      final raw = await _storage.read(key: _todoBlocks);
      if (raw == null) return [];
      return [
        for (final item in jsonDecode(raw) as List<Object?>)
          if (item is Map<String, Object?>) ?SembleTodoBlock.fromJson(item),
      ]..sort((a, b) => a.start.compareTo(b.start));
    } on Object {
      return [];
    }
  }

  Future<void> _saveTodoBlocks(List<SembleTodoBlock> blocks) => _storage.write(
    key: _todoBlocks,
    value: jsonEncode([for (final block in blocks) block.toJson()]),
  );

  Future<void> addTodoBlock(SembleTodoBlock block) async =>
      _saveTodoBlocks([...await todoBlocks(), block]);

  Future<void> removeTodoBlock(String id) async => _saveTodoBlocks([
    for (final block in await todoBlocks())
      if (block.id != id) block,
  ]);

  /// Drops blocks that are over at [now], and those Semble no longer has: a day
  /// inside [first]–[last], the window just read, without its id among
  /// [ruleIds] (removed in Semble itself).
  Future<void> pruneTodoBlocks({
    required Set<String> ruleIds,
    required CivilDate first,
    required CivilDate last,
    required DateTime now,
  }) async {
    final blocks = await todoBlocks();
    final kept = [
      for (final block in blocks)
        if (block.end.isAfter(now) &&
            (ruleIds.contains(block.id) ||
                block.date.compareTo(first) < 0 ||
                block.date.compareTo(last) > 0))
          block,
    ];
    if (kept.length != blocks.length) await _saveTodoBlocks(kept);
  }
}

/// A Semble unavailability created from Todo (build 317): its id, its
/// London day and wall-clock times as sent to Semble.
final class SembleTodoBlock {
  const SembleTodoBlock({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final CivilDate date;
  final String startTime;
  final String endTime;

  DateTime _at(String time) {
    final parts = time.split(':');
    return londonWallClock(
      DateTime.utc(
        date.year,
        date.month,
        date.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      ),
    ).toLocal();
  }

  /// Start and end in the phone's time.
  DateTime get start => _at(startTime);
  DateTime get end => _at(endTime);

  Map<String, Object?> toJson() => {
    'id': id,
    'date': '$date',
    'start': startTime,
    'end': endTime,
  };

  static SembleTodoBlock? fromJson(Map<String, Object?> json) {
    final date = _civil(json['date']);
    final time = RegExp(r'^\d{2}:\d{2}$');
    return switch (json) {
      {
        'id': final String id,
        'start': final String start,
        'end': final String end,
      }
          when date != null && time.hasMatch(start) && time.hasMatch(end) =>
        SembleTodoBlock(id: id, date: date, startTime: start, endTime: end),
      _ => null,
    };
  }
}
