import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/admin_sessions.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/services/admin_sessions_service.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/admin_view.dart';
import 'package:deterministic_todo/ui/views/agenda_event_flows.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Sessioni amministrative» in the shell, on synthetic data only.
void main() {
  // Tuesday 13 October 2026, 09:00: the next slot is B, Wednesday 14 at 16:00.
  DateTime clock() => DateTime(2026, 10, 13, 9);

  Future<(AppDatabase, TaskRepository)> setUpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = TaskRepository(db, deviceId: 'synthetic');
    return (db, repository);
  }

  Future<void> tearDownApp(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  }

  Future<Task> row(AppDatabase db, String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();

  testWidgets('off by default: the app is unchanged', (tester) async {
    final (db, repository) = await setUpApp(tester);
    await repository.create('Attività sintetica');
    await tester.pumpWidget(
      TodoApp(
        repository: repository,
        enablePlatformServices: false,
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsNothing);
    await tester.longPress(find.text('Attività sintetica'));
    await tester.pumpAndSettle();
    expect(find.text('Rimanda al prossimo slot'), findsNothing);
    expect(await db.select(db.projects).get(), isEmpty);
    await tearDownApp(tester, db);
  });

  testWidgets('switch on, defer from the menu and by swiping right', (
    tester,
  ) async {
    final (db, repository) = await setUpApp(tester);
    final first = await repository.create('Modulo sintetico');
    final second = await repository.create('Ricevuta sintetica');
    await tester.pumpWidget(
      TodoApp(
        repository: repository,
        enablePlatformServices: false,
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('settings-admin-sessions'));
    await tester.scrollUntilVisible(toggle, 200);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);

    await tester.longPress(find.text('Modulo sintetico'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-menu-defer')));
    await tester.pumpAndSettle();
    final deferred = await row(db, first);
    expect(deferred.showDate, '2026-10-14');
    expect(deferred.projectId, adminProjectId());
    expect(deferred.sectionId, adminSectionId(AdminSection.inbox));
    expect(find.textContaining('Rimandata a Sessione B'), findsOneWidget);

    await tester.drag(find.text('Ricevuta sintetica'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect((await row(db, second)).showDate, '2026-10-14');

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    // Sparse screen: one line, then only non-empty subsections.
    expect(find.textContaining('Prossimo: Sessione B'), findsOneWidget);
    expect(find.text('2 in coda'), findsOneWidget);
    expect(find.text('Inbox amministrativa · 2'), findsOneWidget);
    expect(find.textContaining('Clinica privata'), findsNothing);
    expect(find.textContaining('In attesa'), findsNothing);
    // Not the session's day: no close button, only the menu.
    expect(find.byKey(const ValueKey('admin-close-session')), findsNothing);
    expect(find.text('Modulo sintetico'), findsOneWidget);
    await tearDownApp(tester, db);
  });

  testWidgets('copy from other projects: proposals, originals untouched', (
    tester,
  ) async {
    final (db, repository) = await setUpApp(tester);
    final project = await repository.createProject('Progetto sintetico');
    final enpam = await repository.create(
      'Pagare ENPAM sintetico',
      projectId: project,
      showDate: '2026-10-01',
    );
    final gmc = await repository.create('Rinnovo GMC sintetico');
    await repository.create('Comprare il pane', projectId: project);
    await tester.pumpWidget(
      TodoApp(
        repository: repository,
        enablePlatformServices: false,
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();
    final admin = AdminSessionsScope.active!;
    await admin.setEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copia dagli altri progetti'));
    await tester.pumpAndSettle();
    expect(find.text('Pagare ENPAM sintetico'), findsOneWidget);
    expect(find.text('Rinnovo GMC sintetico'), findsOneWidget);
    expect(find.text('Comprare il pane'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-copy-confirm')));
    await tester.pumpAndSettle();
    final copies = await (db.select(
      db.tasks,
    )..where((t) => t.projectId.equals(adminProjectId()))).get();
    expect(copies.map((t) => t.externalId).toSet(), {enpam, gmc});
    final enpamCopy = copies.singleWhere((t) => t.externalId == enpam);
    expect(enpamCopy.sectionId, adminSectionId(AdminSection.finance));
    // Undated: no second row next to the original in Oggi/Prossime.
    expect(enpamCopy.showDate, isNull);
    expect(
      copies.singleWhere((t) => t.externalId == gmc).sectionId,
      adminSectionId(AdminSection.career),
    );
    // Originals untouched.
    final original = await row(db, enpam);
    expect(original.projectId, project);
    expect(original.showDate, '2026-10-01');
    expect(original.deletedAt, isNull);
    // Already copied: no second proposal.
    expect(await admin.copyCandidates(), isEmpty);
    await tearDownApp(tester, db);
  });

  test('slots become timed Calendar blocks, apart from events', () {
    const config = AdminSessionsConfig(enabled: true);
    final days = buildAgenda(
      events: const [],
      calendars: const [],
      hiddenCalendarIds: const {},
      first: CivilDate.parse('2026-10-12'),
      days: 7,
      adminSlots: adminSlotsBetween(config, CivilDate.parse('2026-10-12'), 7),
    );
    final entries = [for (final day in days) ...day.entries];
    expect(entries.length, 3);
    expect(
      entries.every((e) => e.isAdminSlot && !e.isTask && !e.allDay),
      isTrue,
    );
    expect(entries.first.calendarIds, [AgendaEntry.adminCalendarId]);
    expect(entries.first.start, DateTime(2026, 10, 12, 16));
    expect(entries.first.adminSlotKey, 'A@2026-10-12');
    // Default merge, used by mirror, reminders and backups: no slots.
    expect(
      mergeAgendaEntries(
        events: const [],
        calendars: const [],
        hiddenCalendarIds: const {},
      ),
      isEmpty,
    );
  });

  testWidgets('a Calendar block opens its slot; skipping is one tap', (
    tester,
  ) async {
    final (db, repository) = await setUpApp(tester);
    final admin = AdminSessionsController(repository, clock: clock);
    await admin.load();
    await admin.setEnabled(true);
    final slot = admin.nextSlot()!;
    final entry = buildAgenda(
      events: const [],
      calendars: const [],
      hiddenCalendarIds: const {},
      first: slot.date,
      days: 1,
      adminSlots: [slot],
    ).single.entries.single;
    String? opened;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final flows = AgendaEventFlows(
      service: AgendaService(db),
      calendars: const [],
      hidden: const {},
      zone: null,
      onOpenAdminSlot: (context, key) async {
        opened = key;
        return showAdminSlotSheet(context, admin, key);
      },
    );
    final changed = flows.show(pageContext, entry);
    await tester.pumpAndSettle();
    expect(opened, 'B@2026-10-14');
    await tester.tap(find.byKey(const ValueKey('admin-slot-skip')));
    await tester.pumpAndSettle();
    expect(await changed, isTrue);
    expect(admin.nextSlot()?.key, 'C@2026-10-18');
    admin.dispose();
    await tearDownApp(tester, db);
  });
}
