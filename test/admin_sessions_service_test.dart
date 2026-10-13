import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/admin_sessions.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/domain/task_planning.dart';
import 'package:deterministic_todo/services/admin_sessions_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic database only: «Sessioni amministrative» writes through the
/// repository, so every change is an explicit, synced and undoable intent.
void main() {
  late AppDatabase db;
  late TaskRepository repo;
  late AdminSessionsController admin;
  // Monday 12 October 2026, 16:50: session A (16:00-16:40) just ended.
  var now = DateTime(2026, 10, 12, 16, 50);

  setUp(() async {
    now = DateTime(2026, 10, 12, 16, 50);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db, deviceId: 'fixture');
    admin = AdminSessionsController(repo, clock: () => now);
    await admin.load();
  });
  tearDown(() => db.close());

  Future<Task> task(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();

  Future<String> create(
    String title, {
    String? date,
    AdminSection? section,
    TaskStatus? status,
  }) => repo.create(
    title,
    showDate: date,
    status: status,
    projectId: section == null ? null : adminProjectId(),
    sectionId: section == null ? null : adminSectionId(section),
  );

  test(
    'off by default; enabling creates one project and five sections',
    () async {
      expect(admin.enabled, isFalse);
      expect(await db.select(db.projects).get(), isEmpty);
      await admin.setEnabled(true);
      await admin.setEnabled(false);
      await admin.setEnabled(true);
      final projects = await db.select(db.projects).get();
      expect(projects.single.id, adminProjectId());
      expect(projects.single.name, 'Amministrazione');
      expect((await db.select(db.projectSections).get()).map((s) => s.name), [
        'Inbox amministrativa',
        'Clinica privata',
        'Finanza e burocrazia',
        'Carriera e compliance',
        'In attesa',
      ]);
      // Persisted on this device.
      final reloaded = AdminSessionsController(repo, clock: () => now);
      await reloaded.load();
      expect(reloaded.enabled, isTrue);
    },
  );

  test('defer: an Inbox task joins the queue on the next slot', () async {
    await admin.setEnabled(true);
    final id = await create('Rinnovo sintetico');
    final outboxBefore = (await db.select(db.outboxEntries).get()).length;
    final result = await admin.defer(await task(id));
    expect(result.outcome, AdminDeferOutcome.slot);
    expect(result.date, CivilDate.parse('2026-10-14'));
    final after = await task(id);
    expect(after.showDate, '2026-10-14');
    expect(after.projectId, adminProjectId());
    expect(after.sectionId, adminSectionId(AdminSection.inbox));
    // Status is the legacy projection of the real clock: not asserted.
    expect(isOpenStatus(after.status), isTrue);
    expect((await db.select(db.outboxEntries).get()).length, outboxBefore + 1);
    // Undo restores placement and date.
    await admin.undo([result.before!]);
    final undone = await task(id);
    expect(undone.showDate, isNull);
    expect(undone.projectId, isNull);
    expect(undone.sectionId, isNull);
  });

  test('defer keeps a specific date before the next slot', () async {
    await admin.setEnabled(true);
    final id = await create(
      'Scadenza sintetica',
      date: '2026-10-13',
      section: AdminSection.finance,
    );
    final result = await admin.defer(await task(id));
    expect(result.outcome, AdminDeferOutcome.keepDate);
    final after = await task(id);
    expect(after.showDate, '2026-10-13');
    expect(after.sectionId, adminSectionId(AdminSection.finance));
  });

  test('defer respects a skipped occurrence', () async {
    await admin.setEnabled(true);
    final b = admin.slotsBetween(CivilDate.parse('2026-10-14'), 1).single;
    await admin.skipOccurrence(b);
    final id = await create('Sintetica');
    final result = await admin.defer(await task(id));
    expect(result.date, CivilDate.parse('2026-10-18'));
  });

  test('close session: residue to the next slot, waiting untouched', () async {
    await admin.setEnabled(true);
    final today = await create(
      'Oggi',
      date: '2026-10-12',
      section: AdminSection.clinic,
    );
    final overdue = await create(
      'Arretrata',
      date: '2026-10-08',
      section: AdminSection.career,
    );
    final later = await create(
      'Data propria',
      date: '2026-10-13',
      section: AdminSection.finance,
    );
    final undated = await create(
      'Da classificare',
      section: AdminSection.inbox,
    );
    final waiting = await create(
      'Risposta attesa',
      date: '2026-10-12',
      section: AdminSection.waiting,
      status: TaskStatus.waiting,
    );
    final outside = await create('Fuori coda', date: '2026-10-12');
    final slot = admin.currentOrLastSlot()!;
    expect(slot.key, 'A@2026-10-12');
    final result = await admin.closeSession(slot);
    expect(result.next?.key, 'B@2026-10-14');
    expect(result.change.count, 2);
    expect((await task(today)).showDate, '2026-10-14');
    expect((await task(overdue)).showDate, '2026-10-14');
    expect((await task(later)).showDate, '2026-10-13');
    expect((await task(undated)).showDate, isNull);
    expect((await task(waiting)).showDate, '2026-10-12');
    expect((await task(waiting)).status, TaskStatus.waiting.name);
    expect((await task(outside)).showDate, '2026-10-12');
    expect(admin.config.isClosed('A@2026-10-12'), isTrue);
    await admin.undo(result.change.before);
    expect((await task(today)).showDate, '2026-10-12');
  });

  test('moving a slot moves its tasks; skipping sends them on', () async {
    await admin.setEnabled(true);
    final id = await create(
      'Sintetica',
      date: '2026-10-14',
      section: AdminSection.finance,
    );
    final b = admin.slotsBetween(CivilDate.parse('2026-10-14'), 1).single;
    final moved = await admin.moveOccurrence(
      b,
      date: CivilDate.parse('2026-10-15'),
      startMinutes: 9 * 60,
      durationMinutes: 30,
    );
    expect(moved.count, 1);
    expect((await task(id)).showDate, '2026-10-15');
    final shifted = admin.occurrence('B@2026-10-14')!;
    expect(shifted.date, CivilDate.parse('2026-10-15'));
    final skipped = await admin.skipOccurrence(shifted);
    expect(skipped.next?.key, 'C@2026-10-18');
    expect((await task(id)).showDate, '2026-10-18');
    expect(
      admin.slotsBetween(CivilDate.parse('2026-10-12'), 7).map((s) => s.key),
      ['A@2026-10-12', 'C@2026-10-18'],
    );
    await admin.restoreOccurrence(shifted);
    expect(
      admin.slotsBetween(CivilDate.parse('2026-10-14'), 1).single.key,
      'B@2026-10-14',
    );
  });

  test('waiting and source: check date, unique external id', () async {
    await admin.setEnabled(true);
    final first = await create('Uno', section: AdminSection.clinic);
    final second = await create('Due', section: AdminSection.clinic);
    await admin.setWaiting(await task(first), CivilDate.parse('2026-10-20'));
    final waiting = await task(first);
    expect(waiting.status, TaskStatus.waiting.name);
    expect(waiting.showDate, '2026-10-20');
    expect(waiting.sectionId, adminSectionId(AdminSection.waiting));
    await admin.setSource(await task(first), AdminSource.semble, 'S-1');
    expect((await task(first)).externalSource, 'admin:semble');
    expect((await task(first)).externalId, 'S-1');
    expect(
      () async =>
          admin.setSource(await task(second), AdminSource.semble, 'S-1'),
      throwsFormatException,
    );
    await admin.setSource(await task(second), AdminSource.gmailOpuk, 'S-1');
    expect((await task(second)).externalSource, 'admin:gmail_opuk');
    // Deferring a waiting item reopens it in the admin Inbox.
    final reopened = await admin.defer(await task(first));
    expect(reopened.outcome, AdminDeferOutcome.slot);
    expect((await task(first)).status, TaskStatus.scheduled.name);
    expect((await task(first)).sectionId, adminSectionId(AdminSection.inbox));
  });

  test('a Todoist task keeps its source', () async {
    await admin.setEnabled(true);
    final id = await create('Importata');
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      const TasksCompanion(
        externalSource: Value('todoist'),
        externalId: Value('123'),
      ),
    );
    expect(
      () async => admin.setSource(await task(id), AdminSource.kcl, null),
      throwsFormatException,
    );
  });

  test('build 265 copies lose their date only, with undo', () async {
    await admin.setEnabled(true);
    final original = await create('Originale sintetico', date: '2026-10-20');
    final copy = await create(
      'Copia sintetica',
      date: '2026-10-14',
      section: AdminSection.finance,
    );
    await admin.repository.planAdministrative(
      await task(copy),
      externalSource: Value(AdminSource.copy.stored),
      externalId: Value(original),
    );
    final other = await create(
      'Altra in coda',
      date: '2026-10-14',
      section: AdminSection.finance,
    );
    final change = await admin.clearCopyDates();
    expect(change.count, 1);
    final cleared = await task(copy);
    expect(cleared.showDate, isNull);
    expect(cleared.sectionId, adminSectionId(AdminSection.finance));
    expect(cleared.externalId, original);
    expect((await task(original)).showDate, '2026-10-20');
    expect((await task(other)).showDate, '2026-10-14');
    await admin.undo(change.before);
    expect((await task(copy)).showDate, '2026-10-14');
  });
}
