import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'task.dart';

/// Sessioni amministrative (sperimentale, build 264): bureaucratic tasks are
/// captured and deferred to a few weekly slots instead of being handled when
/// they appear. Everything here is pure civil-time arithmetic: slots are a
/// weekday plus local minutes in the device's own zone, so a daylight-saving
/// change never moves a 16:00 slot. Nothing is ever rescheduled implicitly.

/// One weekly series (A, B, C…). [weekday] follows [DateTime.weekday].
final class AdminSlotSeries {
  const AdminSlotSeries({
    required this.id,
    required this.label,
    required this.weekday,
    required this.startMinutes,
    required this.durationMinutes,
  }) : assert(weekday >= DateTime.monday && weekday <= DateTime.sunday),
       assert(startMinutes >= 0 && startMinutes < 24 * 60),
       assert(durationMinutes > 0);

  final String id;
  final String label;
  final int weekday;
  final int startMinutes;
  final int durationMinutes;

  AdminSlotSeries copyWith({
    int? weekday,
    int? startMinutes,
    int? durationMinutes,
  }) => AdminSlotSeries(
    id: id,
    label: label,
    weekday: weekday ?? this.weekday,
    startMinutes: startMinutes ?? this.startMinutes,
    durationMinutes: durationMinutes ?? this.durationMinutes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'weekday': weekday,
    'start': startMinutes,
    'duration': durationMinutes,
  };

  static AdminSlotSeries? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final weekday = value['weekday'];
    final start = value['start'];
    final duration = value['duration'];
    if (id is! String ||
        weekday is! int ||
        start is! int ||
        duration is! int ||
        weekday < 1 ||
        weekday > 7 ||
        start < 0 ||
        start >= 24 * 60 ||
        duration <= 0) {
      return null;
    }
    return AdminSlotSeries(
      id: id,
      label: value['label'] as String? ?? id,
      weekday: weekday,
      startMinutes: start,
      durationMinutes: duration,
    );
  }
}

/// A single occurrence moved or skipped. Identified by its series and the
/// date the series would have given it ([originalDate]).
final class AdminSlotOverride {
  const AdminSlotOverride({
    required this.seriesId,
    required this.originalDate,
    this.skipped = false,
    this.date,
    this.startMinutes,
    this.durationMinutes,
  });

  final String seriesId;
  final CivilDate originalDate;
  final bool skipped;
  final CivilDate? date;
  final int? startMinutes;
  final int? durationMinutes;

  String get key => adminOccurrenceKey(seriesId, originalDate);

  Map<String, Object?> toJson() => {
    'series': seriesId,
    'original': originalDate.toString(),
    if (skipped) 'skipped': true,
    if (date != null) 'date': date.toString(),
    'start': ?startMinutes,
    'duration': ?durationMinutes,
  };

  static AdminSlotOverride? fromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final series = value['series'] as String;
      final original = CivilDate.parse(value['original'] as String);
      final date = value['date'] as String?;
      return AdminSlotOverride(
        seriesId: series,
        originalDate: original,
        skipped: value['skipped'] == true,
        date: date == null ? null : CivilDate.parse(date),
        startMinutes: value['start'] as int?,
        durationMinutes: value['duration'] as int?,
      );
    } on Object {
      return null;
    }
  }
}

String adminOccurrenceKey(String seriesId, CivilDate originalDate) =>
    '$seriesId@$originalDate';

/// Kept per device in `app_settings` (key [AdminSessionsConfig.settingsKey]);
/// tasks carry only their date, which is synced as usual.
final class AdminSessionsConfig {
  const AdminSessionsConfig({
    this.enabled = false,
    this.series = defaultSeries,
    this.overrides = const [],
    this.closedKeys = const [],
    this.minutesPerTask = 10,
  });

  static const settingsKey = 'admin_sessions_v1';

  /// The protocol's defaults: Monday and Wednesday afternoon (35–45 min),
  /// Sunday late afternoon (50–60 min). Freely editable.
  static const defaultSeries = [
    AdminSlotSeries(
      id: 'A',
      label: 'Sessione A',
      weekday: DateTime.monday,
      startMinutes: 16 * 60,
      durationMinutes: 40,
    ),
    AdminSlotSeries(
      id: 'B',
      label: 'Sessione B',
      weekday: DateTime.wednesday,
      startMinutes: 16 * 60,
      durationMinutes: 40,
    ),
    AdminSlotSeries(
      id: 'C',
      label: 'Sessione C',
      weekday: DateTime.sunday,
      startMinutes: 17 * 60 + 30,
      durationMinutes: 55,
    ),
  ];

  /// Off by default: with the switch off the app is unchanged.
  final bool enabled;
  final List<AdminSlotSeries> series;
  final List<AdminSlotOverride> overrides;

  /// Occurrences closed with «Chiudi sessione», newest last.
  final List<String> closedKeys;

  /// Rough estimate used only to show the queue size in minutes.
  final int minutesPerTask;

  AdminSessionsConfig copyWith({
    bool? enabled,
    List<AdminSlotSeries>? series,
    List<AdminSlotOverride>? overrides,
    List<String>? closedKeys,
    int? minutesPerTask,
  }) => AdminSessionsConfig(
    enabled: enabled ?? this.enabled,
    series: series ?? this.series,
    overrides: overrides ?? this.overrides,
    closedKeys: closedKeys ?? this.closedKeys,
    minutesPerTask: minutesPerTask ?? this.minutesPerTask,
  );

  AdminSlotSeries? seriesById(String id) =>
      series.where((s) => s.id == id).firstOrNull;

  AdminSlotOverride? overrideFor(String key) =>
      overrides.where((o) => o.key == key).firstOrNull;

  /// Replaces the override of the same occurrence.
  AdminSessionsConfig withOverride(AdminSlotOverride override) => copyWith(
    overrides: List.unmodifiable([
      for (final o in overrides)
        if (o.key != override.key) o,
      override,
    ]),
  );

  /// Back to what the series says.
  AdminSessionsConfig withoutOverride(String key) => copyWith(
    overrides: List.unmodifiable([
      for (final o in overrides)
        if (o.key != key) o,
    ]),
  );

  /// Changes a whole series. Its moves and skips from [from] on refer to
  /// the old weekday and time, so they are dropped; earlier ones stay.
  AdminSessionsConfig withSeries(AdminSlotSeries changed, CivilDate from) =>
      copyWith(
        series: List.unmodifiable([
          for (final s in series) s.id == changed.id ? changed : s,
        ]),
        overrides: List.unmodifiable([
          for (final o in overrides)
            if (o.seriesId != changed.id || o.originalDate.compareTo(from) < 0)
              o,
        ]),
      );

  /// Remembers a closed session; keys older than ~60 days are dropped.
  AdminSessionsConfig closing(String key, CivilDate today) {
    final oldest = today.addDays(-60);
    return copyWith(
      closedKeys: List.unmodifiable([
        for (final k in closedKeys)
          if (k != key && _keyDate(k).compareTo(oldest) >= 0) k,
        key,
      ]),
    );
  }

  bool isClosed(String key) => closedKeys.contains(key);

  String encode() => jsonEncode({
    'enabled': enabled,
    'series': [for (final s in series) s.toJson()],
    'overrides': [for (final o in overrides) o.toJson()],
    'closed': closedKeys,
    'minutes_per_task': minutesPerTask,
  });

  /// Malformed or missing values fall back to the defaults, switched off.
  static AdminSessionsConfig decode(String? value) {
    if (value == null || value.isEmpty) return const AdminSessionsConfig();
    try {
      final json = jsonDecode(value);
      if (json is! Map) return const AdminSessionsConfig();
      final series = [
        for (final item in json['series'] as List? ?? const [])
          ?AdminSlotSeries.fromJson(item),
      ];
      final perTask = json['minutes_per_task'];
      return AdminSessionsConfig(
        enabled: json['enabled'] == true,
        series: series.isEmpty ? defaultSeries : List.unmodifiable(series),
        overrides: List.unmodifiable([
          for (final item in json['overrides'] as List? ?? const [])
            ?AdminSlotOverride.fromJson(item),
        ]),
        closedKeys: List.unmodifiable([
          for (final item in json['closed'] as List? ?? const [])
            if (item is String && item.contains('@')) item,
        ]),
        minutesPerTask: perTask is int && perTask > 0 ? perTask : 10,
      );
    } on FormatException {
      return const AdminSessionsConfig();
    }
  }
}

CivilDate? _tryParse(String value) {
  try {
    return CivilDate.parse(value);
  } on FormatException {
    return null;
  }
}

CivilDate _keyDate(String key) {
  try {
    return CivilDate.parse(key.substring(key.indexOf('@') + 1));
  } on Object {
    return const CivilDate(1970, 1, 1);
  }
}

/// One concrete slot, after moves and skips.
final class AdminSlotOccurrence implements Comparable<AdminSlotOccurrence> {
  const AdminSlotOccurrence({
    required this.seriesId,
    required this.label,
    required this.originalDate,
    required this.date,
    required this.startMinutes,
    required this.durationMinutes,
    this.moved = false,
  });

  final String seriesId;
  final String label;
  final CivilDate originalDate;
  final CivilDate date;
  final int startMinutes;
  final int durationMinutes;

  /// Moved on its own (day, time or length differ from the series).
  final bool moved;

  String get key => adminOccurrenceKey(seriesId, originalDate);

  /// Local wall-clock start: built field by field so a DST change on the
  /// same day never shifts it.
  DateTime get start =>
      DateTime(date.year, date.month, date.day, 0, startMinutes);

  DateTime get end => DateTime(
    date.year,
    date.month,
    date.day,
    0,
    startMinutes + durationMinutes,
  );

  /// Minutes since midnight of [date], comparable to a "now" in minutes.
  bool startsAfter(CivilDate day, int minutes) {
    final byDate = date.compareTo(day);
    return byDate > 0 || (byDate == 0 && startMinutes > minutes);
  }

  @override
  int compareTo(AdminSlotOccurrence other) {
    for (final result in [
      date.compareTo(other.date),
      startMinutes.compareTo(other.startMinutes),
      seriesId.compareTo(other.seriesId),
      originalDate.compareTo(other.originalDate),
    ]) {
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is AdminSlotOccurrence &&
      other.key == key &&
      other.date == date &&
      other.startMinutes == startMinutes &&
      other.durationMinutes == durationMinutes;

  @override
  int get hashCode => Object.hash(key, date, startMinutes, durationMinutes);

  @override
  String toString() => '$key→$date+$startMinutes/$durationMinutes';
}

/// What the series gives for [originalDate], before any override.
AdminSlotOccurrence _regular(AdminSlotSeries series, CivilDate originalDate) =>
    AdminSlotOccurrence(
      seriesId: series.id,
      label: series.label,
      originalDate: originalDate,
      date: originalDate,
      startMinutes: series.startMinutes,
      durationMinutes: series.durationMinutes,
    );

AdminSlotOccurrence _applied(AdminSlotSeries series, AdminSlotOverride o) {
  final date = o.date ?? o.originalDate;
  final start = o.startMinutes ?? series.startMinutes;
  final duration = o.durationMinutes ?? series.durationMinutes;
  return AdminSlotOccurrence(
    seriesId: series.id,
    label: series.label,
    originalDate: o.originalDate,
    date: date,
    startMinutes: start,
    durationMinutes: duration,
    moved:
        date != o.originalDate ||
        start != series.startMinutes ||
        duration != series.durationMinutes,
  );
}

/// Slots on the civil days [first, first + days), sorted. An occurrence
/// moved into the range from outside it is included; one moved out or
/// skipped is not. An override whose original date no longer falls on its
/// series' weekday (the series changed) is ignored.
List<AdminSlotOccurrence> adminSlotsBetween(
  AdminSessionsConfig config,
  CivilDate first,
  int days,
) {
  if (days <= 0) return const [];
  final last = first.addDays(days - 1);
  bool inRange(CivilDate date) =>
      date.compareTo(first) >= 0 && date.compareTo(last) <= 0;
  final overridden = {for (final o in config.overrides) o.key: o};
  final result = <AdminSlotOccurrence>[];
  for (var index = 0; index < days; index++) {
    final date = first.addDays(index);
    final weekday = date.asLocalDate.weekday;
    for (final series in config.series) {
      if (series.weekday != weekday) continue;
      if (overridden.containsKey(adminOccurrenceKey(series.id, date))) {
        continue;
      }
      result.add(_regular(series, date));
    }
  }
  for (final o in config.overrides) {
    if (o.skipped) continue;
    final series = config.seriesById(o.seriesId);
    if (series == null ||
        series.weekday != o.originalDate.asLocalDate.weekday) {
      continue;
    }
    final occurrence = _applied(series, o);
    if (inRange(occurrence.date)) result.add(occurrence);
  }
  return result..sort();
}

/// Weeks searched for a next slot: everything skipped for longer means none.
const adminSlotHorizonDays = 7 * 10;

/// The first slot starting strictly after [today] at [nowMinutes] local
/// minutes, or with [after] the first one following that occurrence.
/// Skipped and moved occurrences are respected. Null without any slot in
/// the next ten weeks.
AdminSlotOccurrence? nextAdminSlot(
  AdminSessionsConfig config, {
  required CivilDate today,
  required int nowMinutes,
  AdminSlotOccurrence? after,
}) {
  final from = after == null ? today : after.date;
  for (final slot in adminSlotsBetween(config, from, adminSlotHorizonDays)) {
    if (after != null) {
      if (slot.key != after.key && slot.compareTo(after) > 0) return slot;
    } else if (slot.startsAfter(today, nowMinutes)) {
      return slot;
    }
  }
  return null;
}

/// The latest slot already started (in progress or finished) within the
/// last [lookbackDays], the one «Chiudi sessione» closes.
AdminSlotOccurrence? currentOrLastAdminSlot(
  AdminSessionsConfig config, {
  required CivilDate today,
  required int nowMinutes,
  int lookbackDays = 7,
}) {
  final first = today.addDays(-lookbackDays);
  final started = [
    for (final slot in adminSlotsBetween(config, first, lookbackDays + 1))
      if (!slot.startsAfter(today, nowMinutes)) slot,
  ];
  return started.isEmpty ? null : started.last;
}

enum AdminDeferOutcome {
  /// The task goes to the slot's date.
  slot,

  /// Its own date comes before the next slot: it is kept.
  keepDate,

  /// No slot in the next ten weeks: nothing changes.
  noSlot,
}

/// «Rimanda al prossimo slot». A task dated after today but before the next
/// slot keeps its specific date (protocol rule); anything else, undated or
/// overdue included, goes to the slot.
({AdminDeferOutcome outcome, CivilDate? date}) adminDeferTarget({
  required String? showDate,
  required CivilDate today,
  required AdminSlotOccurrence? next,
}) {
  if (next == null) return (outcome: AdminDeferOutcome.noSlot, date: null);
  if (showDate != null) {
    final date = _tryParse(showDate);
    if (date != null &&
        date.compareTo(today) > 0 &&
        date.compareTo(next.date) < 0) {
      return (outcome: AdminDeferOutcome.keepDate, date: date);
    }
  }
  return (outcome: AdminDeferOutcome.slot, date: next.date);
}

/// The fields of a task these rules read; tombstones are filtered by the
/// caller's query.
typedef AdminQueueItem = ({String id, String status, String? showDate});

bool _isOpen(AdminQueueItem task) =>
    task.status != TaskStatus.completed.name &&
    task.status != TaskStatus.waiting.name;

/// «Chiudi sessione»: the open, non-waiting tasks of the queue dated on the
/// session's day or earlier. Undated items (still to classify) and items with
/// a later specific date are left alone; waiting items keep their check date.
List<String> adminSessionResidue(
  Iterable<AdminQueueItem> queue,
  AdminSlotOccurrence slot,
) => [
  for (final task in queue)
    if (_isOpen(task) &&
        task.showDate != null &&
        (_tryParse(task.showDate!)?.compareTo(slot.date) ?? 1) <= 0)
      task.id,
];

/// Open tasks of the queue dated on [date]: they follow a slot that is moved
/// or skipped, after confirmation.
List<String> adminTasksOnDate(Iterable<AdminQueueItem> queue, CivilDate date) =>
    [
      for (final task in queue)
        if (_isOpen(task) && task.showDate == date.toString()) task.id,
    ];

/// Size of the queue: a plain count and a rough time, not a target.
final class AdminQueueSummary {
  const AdminQueueSummary({
    required this.open,
    required this.waiting,
    required this.estimatedMinutes,
  });

  final int open;
  final int waiting;
  final int estimatedMinutes;
}

AdminQueueSummary adminQueueSummary(
  Iterable<AdminQueueItem> queue,
  AdminSessionsConfig config,
) {
  var open = 0;
  var waiting = 0;
  for (final task in queue) {
    if (task.status == TaskStatus.completed.name) continue;
    task.status == TaskStatus.waiting.name ? waiting++ : open++;
  }
  return AdminQueueSummary(
    open: open,
    waiting: waiting,
    estimatedMinutes: open * config.minutesPerTask,
  );
}

/// Subsections of «Amministrazione», as project sections with fixed ids.
enum AdminSection {
  inbox('Inbox amministrativa'),
  clinic('Clinica privata'),
  finance('Finanza e burocrazia'),
  career('Carriera e compliance'),
  waiting('In attesa');

  const AdminSection(this.title);
  final String title;

  String get hint => switch (this) {
    AdminSection.inbox => 'Da classificare',
    AdminSection.clinic => 'Semble, Online Psychiatry UK',
    AdminSection.finance => 'Tasse, ENPAM, bollette, rimborsi, commercialista',
    AdminSection.career => 'GMC, SLaM, KCL, training, contratti',
    AdminSection.waiting => 'Bloccate da una risposta esterna',
  };
}

/// Same ids on every device, so enabling the feature twice (phone and Web)
/// never creates two projects: sync merges them as one.
String adminProjectId() =>
    const Uuid().v5(Namespace.url.value, 'deterministic-todo:admin:project');

String adminSectionId(AdminSection section) => const Uuid().v5(
  Namespace.url.value,
  'deterministic-todo:admin:section:${section.name}',
);

const adminExternalSource = 'admin';
const adminProjectName = 'Amministrazione';

/// Origin of an administrative task, stored in `external_source` as
/// `admin:<code>` so that a future import can deduplicate on
/// (`external_source`, `external_id`). Generic labels only: no patient names.
enum AdminSource {
  gmailOpuk('gmail_opuk', 'Gmail OPUK'),
  semble('semble', 'Semble'),
  kcl('kcl', 'KCL'),
  personal('personale', 'Personale'),
  other('altro', 'Altro');

  const AdminSource(this.code, this.label);
  final String code;
  final String label;

  String get stored => 'admin:$code';

  static AdminSource? fromStored(String? value) {
    if (value == null || !value.startsWith('admin:')) return null;
    final code = value.substring(6);
    return AdminSource.values.where((s) => s.code == code).firstOrNull;
  }
}

/// Todoist-imported tasks keep their own source: overwriting it would break
/// re-import deduplication.
bool canSetAdminSource(String? externalSource) =>
    externalSource == null || AdminSource.fromStored(externalSource) != null;
