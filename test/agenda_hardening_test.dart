import 'dart:async';

import 'package:deterministic_todo/data/editor_drafts.dart';
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_event_editor.dart';
import 'package:deterministic_todo/ui/views/agenda_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const calendar = AgendaCalendar(
  id: '1',
  name: 'Test',
  accountName: 'Synthetic',
  writable: true,
  localOnly: true,
);
final date = DateTime(2026, 10, 6, 23);

class _Service extends AgendaService {
  _Service(super.database);
  bool fail = false;
  bool failHide = false;
  AgendaAccess permission = AgendaAccess.granted;
  @override
  Future<AgendaAccess> access() async => permission;
  @override
  Future<String?> deviceZoneLabel() async => 'Europe/London · UTC+1';
  @override
  Future<List<AgendaCalendar>> calendars() async {
    if (fail) throw StateError('synthetic failure');
    return lastCalendars = [calendar];
  }

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async => [
    AgendaSourceEvent(
      instanceId: '1',
      calendarId: '1',
      title: 'Synthetic meeting',
      start: date,
      end: date.add(const Duration(hours: 1)),
      allDay: false,
    ),
  ];
  @override
  Future<void> hideEvent(AgendaEntry entry, {bool series = false}) async {
    if (failHide) throw StateError('synthetic local failure');
    await super.hideEvent(entry, series: series);
  }
}

class _FailingDrafts extends EditorDrafts {
  _FailingDrafts(super.db);
  bool fail = true;
  @override
  Future<void> write(String id, Map<String, dynamic> value) async {
    if (fail) throw StateError('Synthetic storage failure');
    await super.write(id, value);
  }
}

Future<void> openEditor(
  WidgetTester tester, {
  EditorDrafts? drafts,
  Future<void> Function(AgendaEventDraft)? save,
  DateTime? end,
  Future<List<String>> Function()? zones,
  Future<AgendaEventDraft> Function(AgendaEventDraft)? resolve,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AgendaEventEditor(
                  calendars: const [calendar],
                  initialStart: date,
                  initialEnd: end,
                  drafts: drafts,
                  draftId: 'agenda:new',
                  onSave: save,
                  loadTimeZones: zones,
                  resolveTimeZone: resolve,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets(
    'failed save retains editor and fields; pending save cannot run twice',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await openEditor(
        tester,
        save: (_) {
          calls++;
          return pending.future;
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('agenda-event-title')),
        'Draft retained',
      );
      await tester.tap(find.text('Salva'));
      await tester.pump();
      await tester.tap(find.text('Salvataggio…'));
      await tester.pump();
      expect(calls, 1);
      pending.completeError(StateError('synthetic failure'));
      await tester.pumpAndSettle();
      expect(find.text('Draft retained'), findsOneWidget);
      expect(find.textContaining('Salvataggio non riuscito'), findsOneWidget);
      expect(find.text('Salva'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'local draft survives editor destruction and requires explicit recovery',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = EditorDrafts(db);
      await openEditor(tester, drafts: drafts);
      await tester.enterText(
        find.byKey(const ValueKey('agenda-event-title')),
        'Recover me',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpWidget(const SizedBox());
      await openEditor(tester, drafts: drafts);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Riprendi'), findsOneWidget);
      await tester.tap(find.text('Riprendi'));
      await tester.pumpAndSettle();
      expect(find.text('Recover me'), findsOneWidget);
      await tester.tap(find.byTooltip('Annulla'));
      await tester.pumpAndSettle();
      expect(find.text('Modifiche non salvate'), findsOneWidget);
      await tester.tap(find.text('Continua a modificare'));
      await tester.pumpAndSettle();
      expect(find.text('Recover me'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'draft storage failure blocks exit; successful retry permits it',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = _FailingDrafts(db);
      await openEditor(tester, drafts: drafts);
      await tester.enterText(
        find.byKey(const ValueKey('agenda-event-title')),
        'Retain locally',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('Annulla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conserva ed esci'));
      await tester.pumpAndSettle();
      expect(find.text('Retain locally'), findsOneWidget);
      drafts.fail = false;
      await tester.tap(find.byTooltip('Annulla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conserva ed esci'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets('end before start is rejected instead of becoming tomorrow', (
    tester,
  ) async {
    var writes = 0;
    await openEditor(
      tester,
      end: DateTime(2026, 10, 6, 22),
      save: (_) async {
        writes++;
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('agenda-event-title')),
      'Invalid duration',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Salva'), findsOneWidget);
    expect(find.textContaining('La fine deve essere dopo'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('multi-day timed events retain end date and show duration', (
    tester,
  ) async {
    AgendaEventDraft? saved;
    await openEditor(
      tester,
      end: date.add(const Duration(hours: 25)),
      save: (d) async => saved = d,
    );
    await tester.enterText(
      find.byKey(const ValueKey('agenda-event-title')),
      'Overnight',
    );
    expect(find.text('Durata: 25 h 0 min'), findsOneWidget);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(saved!.end, date.add(const Duration(hours: 25)));
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
    'choosing a zone passes civil input to the resolver before saving',
    (tester) async {
      AgendaEventDraft? saved;
      await openEditor(
        tester,
        zones: () async => ['Europe/Rome'],
        resolve: (d) async {
          expect(d.timeZone, 'Europe/Rome');
          return d;
        },
        save: (d) async => saved = d,
      );
      await tester.enterText(
        find.byKey(const ValueKey('agenda-event-title')),
        'Zoned',
      );
      await tester.ensureVisible(find.text('Scegli fuso orario'));
      await tester.tap(find.text('Scegli fuso orario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Europe/Rome'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(saved!.timeZone, 'Europe/Rome');
    },
  );

  testWidgets('failed refresh keeps list; permission revocation hides it', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = _Service(db);
    addTearDown(db.close);
    await service.saveViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: service, today: CivilDate(2026, 10, 6)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synthetic meeting'), findsOneWidget);
    service.fail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic meeting'), findsOneWidget);
    expect(find.textContaining('Aggiornamento non riuscito'), findsOneWidget);
    service.permission = AgendaAccess.denied;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic meeting'), findsNothing);
    expect(find.text('Apri impostazioni'), findsOneWidget);
  });

  test(
    'old month migrates once; explicit month and other views survive',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'agenda_view_mode_v2',
              value: 'month',
            ),
          );
      final service = _Service(db);
      expect(await service.viewMode(), AgendaViewMode.fourWeeks);
      await service.saveViewMode(AgendaViewMode.month);
      expect(await _Service(db).viewMode(), AgendaViewMode.month);
      await (db.delete(
        db.appSettings,
      )..where((s) => s.key.equals(AgendaService.viewModeKey))).go();
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: 'agenda_view_mode_v2',
              value: 'list',
            ),
          );
      expect(await _Service(db).viewMode(), AgendaViewMode.list);
    },
  );

  testWidgets('four weeks begin on Monday across year boundaries', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaView(service: _Service(db), today: CivilDate(2027, 1, 3)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-day-2026-12-28')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-day-2027-01-24')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-day-2027-01-25')), findsNothing);
  });

  testWidgets(
    'mode switch keeps the selected day and filters reset explicitly',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final service = _Service(db);
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaView(service: service, today: CivilDate(2026, 10, 6)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView).first, const Offset(-700, 0));
      await tester.pumpAndSettle();
      final modeMenu = find.byType(PopupMenuButton<AgendaViewMode>);
      await tester.tap(modeMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elenco').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('nov'), findsWidgets);
      expect(find.text('Azzera filtri'), findsNothing);
      expect(find.textContaining('festività nascoste'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('agenda-choose-calendars')));
      await tester.pumpAndSettle();
      expect(find.textContaining('festività nascoste'), findsOneWidget);
      await tester.tap(find.text('Azzera filtri'));
      await tester.pumpAndSettle();
      expect((await service.filter()).hideHolidays, true);
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();
      expect((await service.filter()).hideHolidays, false);
      expect(find.text('Azzera filtri'), findsNothing);
    },
  );

  test(
    'copy retry uses the same identity after failure hiding the original',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _Service(db)..failHide = true;
      final keys = <String>[];
      const channel = MethodChannel('app.deterministic.todo/agenda');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'copyLocalEvent') {
              keys.add(
                ((call.arguments as Map)['event'] as Map)['copy_key'] as String,
              );
              return 'copy';
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final entry = AgendaEntry(
        instanceId: 'original',
        calendarIds: const ['external'],
        title: 'Synthetic',
        start: date,
        end: date.add(const Duration(hours: 1)),
        allDay: false,
      );
      final draft = AgendaEventDraft(
        calendarId: '1',
        title: 'Copy',
        start: date,
        end: date.add(const Duration(hours: 1)),
      );
      await expectLater(service.copyInTodo(entry, draft), throwsStateError);
      service.failHide = false;
      await service.copyInTodo(entry, draft);
      expect(keys.length, 2);
      expect(keys[0], keys[1]);
      expect((await service.filter()).hiddenEvents.length, 1);
    },
  );
}
