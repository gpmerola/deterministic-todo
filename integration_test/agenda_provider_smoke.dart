// Run only on an Android emulator via tools/agenda_provider_smoke.py.
// Uses an in-memory Todo DB and uniquely marked synthetic provider events.
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.deterministic.todo/agenda');
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final service = AgendaService(db);
  String status = 'FAIL';
  String phase = 'copy';
  String? cleanupId;
  final seriesCleanup = <String>[];
  String? seriesParent;
  try {
    if (await service.requestAccess() != AgendaAccess.granted) {
      throw StateError('Permission missing');
    }
    final target = (await service.localCalendar())!;
    final start = DateTime(2026, 10, 8, 10);
    final source = AgendaEntry(
      instanceId: 'qa229-provider-smoke',
      calendarIds: const ['synthetic'],
      title: 'Synthetic source',
      start: start,
      end: start.add(const Duration(hours: 1)),
      allDay: false,
    );
    AgendaEventDraft draft(String title) => AgendaEventDraft(
      calendarId: target.id,
      title: title,
      start: start,
      end: start.add(const Duration(hours: 25)),
      notes: 'Synthetic note',
    );
    Future<List<Map<Object?, Object?>>> copies() async => [
      for (final row in (await channel.invokeListMethod<Map<Object?, Object?>>(
        'localEvents',
        {'calendarId': target.id},
      ))!)
        if (row['title'] == 'QA229-first' || row['title'] == 'QA229-retry') row,
    ];
    await service.copyInTodo(source, draft('QA229-first'));
    final first = await copies();
    if (first.length != 1 || first.single['copy_key'] == null) {
      throw StateError('First copy');
    }
    cleanupId = first.single['id'].toString();
    // Simulate the recoverable second step not having completed.
    await service.showHiddenEvent(source.key);
    phase = 'copy_retry';
    await service.copyInTodo(source, draft('QA229-retry'));
    final second = await copies();
    if (second.length != 1 ||
        second.single['id'].toString() != cleanupId ||
        second.single['title'] != 'QA229-retry') {
      throw StateError('Duplicate or lost update');
    }
    // Restore the same native record twice: neither may create another copy.
    phase = 'copy_restore';
    for (var i = 0; i < 2; i++) {
      final count = await channel.invokeMethod<int>('restoreLocalEvents', {
        'calendarId': target.id,
        'events': second,
      });
      if (count != 0) throw StateError('Restore duplicated');
    }
    // Restore a missing series and a moved occurrence, then repeat the restore.
    phase = 'series_restore';
    final seriesStart = DateTime.utc(2026, 10, 8, 9).millisecondsSinceEpoch;
    final occurrence = seriesStart + const Duration(days: 7).inMilliseconds;
    final backup = <Map<String, Object?>>[
      {
        'id': 991,
        'title': 'QA229-series',
        'dtstart': seriesStart,
        'dtend': seriesStart + 3600000,
        'all_day': 0,
        'tz': 'Europe/London',
        'rrule': 'FREQ=WEEKLY;COUNT=3',
        'description': 'Synthetic series note',
      },
      {
        'id': 992,
        'title': 'QA229-exception',
        'dtstart': occurrence + 1800000,
        'dtend': occurrence + 5400000,
        'all_day': 0,
        'tz': 'Europe/London',
        'original_id': 991,
        'original_instance_time': occurrence,
        'original_all_day': 0,
      },
    ];
    await channel.invokeMethod<int>('restoreLocalEvents', {
      'calendarId': target.id,
      'events': backup,
    });
    final restored =
        (await channel.invokeListMethod<Map<Object?, Object?>>('localEvents', {
              'calendarId': target.id,
            }))!
            .where(
              (r) =>
                  r['title'] == 'QA229-series' ||
                  r['title'] == 'QA229-exception',
            )
            .toList();
    seriesCleanup.addAll([
      for (final r in restored)
        if (r['title'] == 'QA229-exception') r['id'].toString(),
    ]);
    for (final r in restored) {
      if (r['title'] == 'QA229-series') seriesParent = r['id'].toString();
    }
    phase = 'series_count_${restored.length}';
    if (restored.length != 2) throw StateError('Series restore');
    phase = 'series_relation';
    final parent = restored.singleWhere((r) => r['title'] == 'QA229-series');
    final exception = restored.singleWhere(
      (r) => r['title'] == 'QA229-exception',
    );
    if (exception['original_id'].toString() != parent['id'].toString() ||
        parent['description'] != 'Synthetic series note') {
      throw StateError('Series relationship');
    }
    phase = 'series_retry';
    if (await channel.invokeMethod<int>('restoreLocalEvents', {
          'calendarId': target.id,
          'events': backup,
        }) !=
        0) {
      throw StateError('Series retry duplicated');
    }
    // One occurrence of a series: editing or deleting it must leave the
    // other occurrences alone (fixed in device_calendar_plus 0.9).
    phase = 'occurrence_edit';
    Future<List<Map<Object?, Object?>>> seriesRows() async => [
      for (final row in (await channel.invokeListMethod<Map<Object?, Object?>>(
        'instances',
        {
          'start': seriesStart - 3600000,
          'end': seriesStart + const Duration(days: 21).inMilliseconds,
          'calendarIds': [target.id],
        },
      ))!)
        if ('${row['title']}'.startsWith('QA229-') &&
            row['title'] != 'QA229-retry' &&
            row['canceled'] != true)
          row,
    ];
    List<String> titles(List<Map<Object?, Object?>> rows) =>
        [for (final row in rows) '${row['title']}']..sort();
    final before = await seriesRows();
    phase = 'occurrence_list_${before.length}';
    if (titles(before).join(',') !=
        'QA229-exception,QA229-series,QA229-series') {
      throw StateError('Series occurrences');
    }
    final firstId = before
        .firstWhere((r) => r['start'] == seriesStart)['instanceId']
        .toString();
    await service.updateEvent(
      firstId,
      AgendaEventDraft(
        calendarId: target.id,
        title: 'QA229-single',
        start: DateTime.fromMillisecondsSinceEpoch(seriesStart),
        end: DateTime.fromMillisecondsSinceEpoch(seriesStart + 3600000),
      ),
    );
    final edited = await seriesRows();
    phase = 'occurrence_edited';
    if (titles(edited).join(',') !=
        'QA229-exception,QA229-series,QA229-single') {
      throw StateError('Occurrence edit touched the series');
    }
    phase = 'occurrence_flag';
    final single = edited.firstWhere((r) => r['title'] == 'QA229-single');
    final normal = edited.firstWhere((r) => r['title'] == 'QA229-series');
    if (single['changedOccurrence'] != true ||
        normal['changedOccurrence'] == true) {
      throw StateError('Changed occurrence flag');
    }
    phase = 'occurrence_delete';
    await service.deleteEvent(
      edited
          .firstWhere((r) => r['title'] == 'QA229-single')['instanceId']
          .toString(),
    );
    final deleted = await seriesRows();
    if (titles(deleted).join(',') != 'QA229-exception,QA229-series') {
      throw StateError('Occurrence delete touched the series');
    }
    // The whole series, chosen from one of its changed occurrences.
    phase = 'series_delete_from_exception';
    await service.deleteEvent(
      deleted
          .firstWhere((r) => r['title'] == 'QA229-exception')['instanceId']
          .toString(),
      series: true,
    );
    if ((await seriesRows()).isNotEmpty) {
      throw StateError('Series delete left occurrences');
    }
    seriesCleanup.clear();
    seriesParent = null;
    phase = 'zone';
    final zones = await service.timeZones();
    if (!zones.contains('Europe/Rome')) throw StateError('Missing zone');
    final resolved = await service.resolveTimeZone(
      AgendaEventDraft(
        calendarId: target.id,
        title: 'Synthetic zone',
        timeZone: 'Europe/Rome',
        start: DateTime.utc(2026, 10, 8, 10),
        end: DateTime.utc(2026, 10, 8, 11),
      ),
    );
    if (resolved.start != DateTime.utc(2026, 10, 8, 8)) {
      throw StateError('Wrong instant');
    }
    status = 'PASS';
  } catch (error) {
    // Never log provider messages, titles, notes, IDs or account data.
    status =
        'FAIL_${phase}_${error is PlatformException ? error.code : error.runtimeType}';
  } finally {
    for (final id in seriesCleanup) {
      try {
        await service.deleteEvent(id);
      } catch (_) {
        status = 'FAIL_CLEANUP';
      }
    }
    // A bare series ID is refused by deleteEvent since the plugin's 0.10.
    if (seriesParent != null) {
      try {
        await service.deleteEvent(seriesParent, series: true);
      } catch (_) {
        status = 'FAIL_CLEANUP';
      }
    }
    if (cleanupId != null) {
      try {
        await service.deleteEvent(cleanupId);
      } catch (_) {
        status = 'FAIL_CLEANUP';
      }
    }
    // Nothing synthetic may survive the run.
    try {
      final left = (await channel.invokeListMethod<Map<Object?, Object?>>(
        'localEvents',
        {'calendarId': (await service.localCalendar())!.id},
      ))!.where((r) => '${r['title']}'.startsWith('QA229-'));
      if (left.isNotEmpty && status == 'PASS') status = 'FAIL_LEFTOVER';
    } catch (_) {
      if (status == 'PASS') status = 'FAIL_LEFTOVER_CHECK';
    }
    await db.close();
  }
  // Technical result only, consumed by the host runner.
  debugPrint('AGENDA_PROVIDER_SMOKE:$status');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text('Agenda provider: $status'))),
    ),
  );
}
