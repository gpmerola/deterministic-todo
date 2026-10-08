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

/// Choices of a restored backup for calendars this phone does not have yet,
/// e.g. KCL before its account is set up again (build 228). They stay in
/// the backup and apply by themselves when the calendar appears, so the
/// order of "Ripristina" and account setup does not matter.
final class UnmatchedAgendaSettings {
  const UnmatchedAgendaSettings({
    this.choices = const {},
    this.colors = const {},
    this.main,
    this.mainBefore,
    this.ai,
    this.aiBefore,
  });

  static const empty = UnmatchedAgendaSettings();

  /// By [agendaCalendarKey].
  final Map<String, bool> choices;
  final Map<String, String> colors;

  /// «Nuovi eventi in» and the ✨ calendar of the backup, by key, with this
  /// phone's own choice when they were set aside: a choice the user makes
  /// afterwards wins over them.
  final String? main;
  final String? mainBefore;
  final String? ai;
  final String? aiBefore;

  bool get isEmpty =>
      choices.isEmpty && colors.isEmpty && main == null && ai == null;

  Map<String, Object?> toJson() => {
    'choices': choices,
    'colors': colors,
    'main': main,
    'main_before': mainBefore,
    'ai': ai,
    'ai_before': aiBefore,
  };

  static UnmatchedAgendaSettings fromJson(Object? value) {
    if (value is! Map) return empty;
    return UnmatchedAgendaSettings(
      choices: _typed<bool>(value['choices']),
      colors: _typed<String>(value['colors']),
      main: value['main'] as String?,
      mainBefore: value['main_before'] as String?,
      ai: value['ai'] as String?,
      aiBefore: value['ai_before'] as String?,
    );
  }

  static Map<String, T> _typed<T>(Object? value) => {
    if (value is Map)
      for (final entry in value.entries)
        if (entry.key is String && entry.value is T)
          entry.key as String: entry.value as T,
  };

  /// Settings of a backup ([settings], by key) split against the calendars
  /// of this phone ([ids]: key → id): what applies now, by id, and what is
  /// set aside. [main] and [ai] are this phone's current choices.
  static ({AgendaSettingsById now, UnmatchedAgendaSettings later}) split(
    Map<Object?, Object?> settings,
    Map<String, String> ids, {
    required String? main,
    required String? ai,
  }) {
    final choices = _typed<bool>(settings['choices']);
    final colors = _typed<String>(settings['colors']);
    final mainKey = settings['main'] as String?;
    final aiKey = settings['ai'] as String?;
    return (
      now: (
        choices: {
          for (final entry in choices.entries)
            if (ids[entry.key] != null) ids[entry.key]!: entry.value,
        },
        colors: {
          for (final entry in colors.entries)
            if (ids[entry.key] != null) ids[entry.key]!: entry.value,
        },
        main: ids[mainKey],
        ai: ids[aiKey],
      ),
      later: UnmatchedAgendaSettings(
        choices: {
          for (final entry in choices.entries)
            if (ids[entry.key] == null) entry.key: entry.value,
        },
        colors: {
          for (final entry in colors.entries)
            if (ids[entry.key] == null) entry.key: entry.value,
        },
        main: mainKey != null && ids[mainKey] == null ? mainKey : null,
        mainBefore: mainKey != null && ids[mainKey] == null ? main : null,
        ai: aiKey != null && ids[aiKey] == null ? aiKey : null,
        aiBefore: aiKey != null && ids[aiKey] == null ? ai : null,
      ),
    );
  }

  /// Set-aside settings as a backup holds them, minus «Nuovi eventi in» or
  /// ✨ when the user has chosen another calendar since ([main], [ai]).
  Map<String, Object?> asSettings({
    required String? main,
    required String? ai,
  }) => {
    'choices': choices,
    'colors': colors,
    'main': main == mainBefore ? this.main : null,
    'ai': ai == aiBefore ? this.ai : null,
  };
}

/// Choices to apply on this phone, by calendar id.
typedef AgendaSettingsById = ({
  Map<String, bool> choices,
  Map<String, String> colors,
  String? main,
  String? ai,
});

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
  UnmatchedAgendaSettings unmatched = UnmatchedAgendaSettings.empty,
}) {
  final aside = unmatched.asSettings(main: mainCalendarId, ai: aiCalendarId);
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
        ...unmatched.choices,
        for (final entry in choices.entries)
          if (keys[entry.key] != null) keys[entry.key]!: entry.value,
      },
      'colors': {
        ...unmatched.colors,
        for (final entry in colors.entries)
          if (keys[entry.key] != null) keys[entry.key]!: entry.value,
      },
      'main': aside['main'] ?? keys[mainCalendarId],
      'ai': aside['ai'] ?? keys[aiCalendarId],
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

  /// [UnmatchedAgendaSettings] of the last restore, until their calendars
  /// appear on this phone.
  static const unmatchedKey = 'agenda_backup_unmatched';

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

  Future<UnmatchedAgendaSettings> _unmatched() async {
    final row = await (_database.select(
      _database.appSettings,
    )..where((setting) => setting.key.equals(unmatchedKey))).getSingleOrNull();
    if (row == null) return UnmatchedAgendaSettings.empty;
    try {
      return UnmatchedAgendaSettings.fromJson(jsonDecode(row.value));
    } on FormatException {
      return UnmatchedAgendaSettings.empty;
    }
  }

  Future<void> _saveUnmatched(UnmatchedAgendaSettings value) async {
    if (value.isEmpty) {
      await (_database.delete(
        _database.appSettings,
      )..where((setting) => setting.key.equals(unmatchedKey))).go();
      return;
    }
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: unmatchedKey,
            value: jsonEncode(value.toJson()),
          ),
        );
  }

  /// Applies [settings] (by key) for the calendars this phone has; sets the
  /// rest aside. Used by the restore and, for set-aside choices, whenever
  /// the backup is built: a calendar set up later gets its choices then.
  Future<UnmatchedAgendaSettings> _applyByKey(
    Map<Object?, Object?> settings,
    List<AgendaCalendar> calendars, {
    String? mainBefore,
    String? aiBefore,
    bool fromRestore = false,
  }) async {
    final ids = {
      for (final calendar in calendars)
        agendaCalendarKey(calendar): calendar.id,
    };
    final main = await service.lastEventCalendar();
    final ai = await service.aiEventCalendar();
    final split = UnmatchedAgendaSettings.split(
      settings,
      ids,
      main: main,
      ai: ai,
    );
    final now = split.now;
    if (now.choices.isNotEmpty) {
      await service.saveCalendarChoices({
        ...await service.calendarChoices(),
        ...now.choices,
      });
    }
    if (now.colors.isNotEmpty) {
      await service.saveCalendarColors({
        ...await service.calendarColors(),
        ...now.colors,
      });
    }
    // A set-aside «Nuovi eventi in» applies only if the user has not chosen
    // another calendar since the restore.
    if (now.main != null && (fromRestore || main == mainBefore)) {
      await service.saveEventCalendar(now.main!);
    }
    if (now.ai != null && (fromRestore || ai == aiBefore)) {
      await service.saveAiEventCalendar(now.ai);
    }
    final later = split.later;
    // Still waiting: keep the phone's choice as it was at the restore.
    return UnmatchedAgendaSettings(
      choices: later.choices,
      colors: later.colors,
      main: later.main,
      mainBefore: fromRestore ? later.mainBefore : mainBefore,
      ai: later.ai,
      aiBefore: fromRestore ? later.aiBefore : aiBefore,
    );
  }

  /// Applies set-aside choices whose calendars are now on this phone;
  /// returns what is still waiting.
  @visibleForTesting
  Future<UnmatchedAgendaSettings> applySetAside() async {
    final unmatched = await _unmatched();
    if (unmatched.isEmpty) return unmatched;
    final remaining = await _applyByKey(
      unmatched.asSettings(
        main: await service.lastEventCalendar(),
        ai: await service.aiEventCalendar(),
      ),
      await service.calendars(),
      mainBefore: unmatched.mainBefore,
      aiBefore: unmatched.aiBefore,
    );
    if (canonicalJson(remaining.toJson()) !=
        canonicalJson(unmatched.toJson())) {
      await _saveUnmatched(remaining);
    }
    return remaining;
  }

  Future<Map<String, Object?>> _build() async {
    final unmatched = await applySetAside();
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
      unmatched: unmatched,
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
    if (settings is Map) await restoreSettings(settings);
    await _saveBase(backup.hash);
    pending.value = null;
    // The merged state becomes the new backup.
    await save();
    return added;
  }

  @visibleForTesting
  Future<void> restoreSettings(Map<Object?, Object?> settings) async {
    final filter = settings['filter'];
    if (filter is Map) {
      try {
        await service.saveFilter(AgendaService.filterFromJson(filter));
      } on TypeError {
        // A malformed filter is skipped; the rest still restores.
      }
    }
    await _saveUnmatched(
      await _applyByKey(settings, await service.calendars(), fromRestore: true),
    );
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
