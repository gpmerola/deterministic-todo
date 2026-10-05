import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../domain/agenda.dart';
import 'agenda_service.dart';

/// Calendar ids are local to a phone: the backup names calendars by account
/// and name, which a new phone with the same accounts shares.
String agendaCalendarKey(AgendaCalendar calendar) =>
    '${calendar.accountName}\u001f${calendar.name}';

/// JSON with object keys sorted at every level, so the same content always
/// gives the same hash (native rows arrive as unordered maps).
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _sorted(value[key]),
  },
  List() => [for (final item in value) _sorted(item)],
  _ => value,
};

/// What only Todo's Agenda holds (build 227): the events of the phone-only
/// Todo calendar, notes and repetitions included, and the Agenda choices.
/// Everything else lives in the accounts that sync it.
Map<String, Object?> buildAgendaBackup({
  required List<AgendaCalendar> calendars,
  required List<Map<Object?, Object?>> localEvents,
  required AgendaFilter filter,
  required Map<String, bool> choices,
  required Map<String, String> colors,
  required String? mainCalendarId,
  required String? aiCalendarId,
  required AgendaViewMode viewMode,
  required Set<String> taskLinks,
}) {
  final keys = {
    for (final calendar in calendars) calendar.id: agendaCalendarKey(calendar),
  };
  final local = calendars.where((calendar) => calendar.localOnly).firstOrNull;
  return {
    'version': 1,
    'calendar': local == null ? null : {'color': local.colorHex},
    'events': localEvents,
    'settings': {
      'filter': AgendaService.filterToJson(filter),
      'choices': {
        for (final entry in choices.entries)
          if (keys[entry.key] != null) keys[entry.key]!: entry.value,
      },
      'colors': {
        for (final entry in colors.entries)
          if (keys[entry.key] != null) keys[entry.key]!: entry.value,
      },
      'main': keys[mainCalendarId],
      'ai': keys[aiCalendarId],
      'view_mode': viewMode.name,
      'task_links': taskLinks.toList()..sort(),
    },
  };
}

String agendaBackupHash(Map<String, Object?> backup) =>
    sha256.convert(utf8.encode(canonicalJson(backup))).toString();

/// The backup stored on the account.
final class RemoteAgendaBackup {
  const RemoteAgendaBackup({
    required this.hash,
    required this.savedAt,
    required this.payload,
  });

  final String hash;
  final DateTime savedAt;
  final Map<String, Object?> payload;

  int get eventCount => (payload['events'] as List?)?.length ?? 0;

  int get hiddenCount {
    final settings = payload['settings'];
    final filter = settings is Map ? settings['filter'] : null;
    final hidden = filter is Map ? filter['hidden_events'] : null;
    return hidden is List ? hidden.length : 0;
  }
}

enum AgendaBackupStatus {
  saved,
  unchanged,

  /// The account holds a backup this phone has not restored: nothing is
  /// overwritten until the user restores it or replaces it explicitly.
  conflict,
  skipped,
  failed,
}

/// Keeps the Supabase backup of Todo's own Agenda data current, on the
/// mirror's schedule (start, resume, changes, background job). Uploads only
/// when the content changed.
class AgendaBackup {
  AgendaBackup({
    required this.service,
    required this.client,
    required this.deviceId,
  });

  /// Hash of the backup this phone last saved or restored. The server
  /// refuses to replace any other (see `save_agenda_backup_v1`).
  static const baseKey = 'agenda_backup_base';

  static const _channel = MethodChannel('app.deterministic.todo/agenda');

  /// A backup waiting for "Ripristina" (or for "Usa questo telefono").
  static final pending = ValueNotifier<RemoteAgendaBackup?>(null);

  /// The phone's instance, for the restore actions of the Agenda.
  static AgendaBackup? current;

  final AgendaService service;
  final SupabaseClient client;
  final String deviceId;
  bool _busy = false;

  AppDatabase get _database => service.database;

  Future<String?> _base() async => (await (_database.select(
    _database.appSettings,
  )..where((setting) => setting.key.equals(baseKey))).getSingleOrNull())?.value;

  Future<void> _saveBase(String hash) => _database
      .into(_database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: baseKey, value: hash),
      );

  Future<Map<String, Object?>> _build() async {
    final calendars = await service.calendars();
    final local = calendars.where((c) => c.localOnly).firstOrNull;
    final events = local == null
        ? const <Map<Object?, Object?>>[]
        : await _channel.invokeListMethod<Map<Object?, Object?>>(
                'localEvents',
                {'calendarId': local.id},
              ) ??
              const [];
    return buildAgendaBackup(
      calendars: calendars,
      localEvents: events,
      filter: await service.filter(),
      choices: await service.calendarChoices(),
      colors: await service.calendarColors(),
      mainCalendarId: await service.lastEventCalendar(),
      aiCalendarId: await service.aiEventCalendar(),
      viewMode: await service.viewMode(),
      taskLinks: await service.taskLinks.keys(),
    );
  }

  /// Uploads the backup if it changed since the last save. With [force]
  /// it replaces whatever the account holds ("Usa questo telefono").
  Future<AgendaBackupStatus> save({bool force = false}) async {
    if (_busy || client.auth.currentSession == null) {
      return AgendaBackupStatus.skipped;
    }
    _busy = true;
    try {
      if (await service.access() != AgendaAccess.granted) {
        return AgendaBackupStatus.skipped;
      }
      final backup = await _build();
      final hash = agendaBackupHash(backup);
      var base = await _base();
      if (!force && base == hash) return AgendaBackupStatus.unchanged;
      if (force) base = (await remote())?.hash;
      final status = await client.rpc<String>(
        'save_agenda_backup_v1',
        params: {
          'backup': {...backup, 'device_id': deviceId},
          'backup_hash': hash,
          'base_hash': base,
        },
      );
      switch (status) {
        case 'saved' || 'unchanged':
          await _saveBase(hash);
          pending.value = null;
          return status == 'saved'
              ? AgendaBackupStatus.saved
              : AgendaBackupStatus.unchanged;
        case 'conflict':
          pending.value = await remote();
          return AgendaBackupStatus.conflict;
        default:
          return AgendaBackupStatus.failed;
      }
    } catch (_) {
      // Not logged: the backup carries event titles and notes.
      return AgendaBackupStatus.failed;
    } finally {
      _busy = false;
    }
  }

  Future<RemoteAgendaBackup?> remote() async {
    final row = await client
        .from('agenda_backups')
        .select('hash, saved_at, payload')
        .maybeSingle();
    if (row == null) return null;
    return RemoteAgendaBackup(
      hash: row['hash'] as String,
      savedAt: DateTime.parse(row['saved_at'] as String).toLocal(),
      payload: Map<String, Object?>.from(row['payload'] as Map),
    );
  }

  /// Restores [backup] on this phone: missing Todo events are added (none
  /// twice), the Agenda choices replace this phone's for the calendars it
  /// has. Returns the number of events added.
  Future<int> restore(RemoteAgendaBackup backup) async {
    final payload = backup.payload;
    final events = [
      for (final event in payload['events'] as List? ?? const [])
        if (event is Map) Map<String, Object?>.from(event),
    ];
    var added = 0;
    if (events.isNotEmpty) {
      final local = await service.localCalendar();
      added =
          await _channel.invokeMethod<int>('restoreLocalEvents', {
            'calendarId': local!.id,
            'events': events,
          }) ??
          0;
    }
    final settings = payload['settings'];
    if (settings is Map) await _restoreSettings(settings);
    await _saveBase(backup.hash);
    pending.value = null;
    // The merged state becomes the new backup.
    await save();
    return added;
  }

  Future<void> _restoreSettings(Map<Object?, Object?> settings) async {
    final calendars = await service.calendars();
    final ids = {
      for (final calendar in calendars)
        agendaCalendarKey(calendar): calendar.id,
    };
    Map<String, T> byId<T>(Object? value) => {
      if (value is Map)
        for (final entry in value.entries)
          if (ids[entry.key] != null && entry.value is T)
            ids[entry.key]!: entry.value as T,
    };
    final filter = settings['filter'];
    if (filter is Map) {
      try {
        await service.saveFilter(AgendaService.filterFromJson(filter));
      } on TypeError {
        // A malformed filter is skipped; the rest still restores.
      }
    }
    final choices = byId<bool>(settings['choices']);
    if (choices.isNotEmpty) {
      await service.saveCalendarChoices({
        ...await service.calendarChoices(),
        ...choices,
      });
    }
    final colors = byId<String>(settings['colors']);
    if (colors.isNotEmpty) {
      await service.saveCalendarColors({
        ...await service.calendarColors(),
        ...colors,
      });
    }
    final main = ids[settings['main']];
    if (main != null) await service.saveEventCalendar(main);
    final ai = ids[settings['ai']];
    if (ai != null) await service.saveAiEventCalendar(ai);
    final mode = AgendaViewMode.values
        .where((mode) => mode.name == settings['view_mode'])
        .firstOrNull;
    if (mode != null) await service.saveViewMode(mode);
    final links = settings['task_links'];
    if (links is List) {
      await service.taskLinks.addKeys(links.whereType<String>());
    }
  }
}
