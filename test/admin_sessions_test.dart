import 'package:deterministic_todo/domain/admin_sessions.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure rules of «Sessioni amministrative»: civil dates and local minutes
/// only, so every case is deterministic whatever the host zone.
void main() {
  const enabled = AdminSessionsConfig(enabled: true);
  CivilDate d(String value) => CivilDate.parse(value);
  int at(int hour, [int minute = 0]) => hour * 60 + minute;

  group('slots', () {
    test('defaults: Monday and Wednesday 16:00, Sunday 17:30', () {
      final slots = adminSlotsBetween(enabled, d('2026-10-12'), 7);
      expect(
        [for (final s in slots) s.toString()],
        [
          'A@2026-10-12→2026-10-12+960/40',
          'B@2026-10-14→2026-10-14+960/40',
          'C@2026-10-18→2026-10-18+1050/55',
        ],
      );
    });

    test('next slot is strictly after now', () {
      // Monday 15:59: A today. Monday 16:00 (started): B on Wednesday.
      expect(
        nextAdminSlot(
          enabled,
          today: d('2026-10-12'),
          nowMinutes: at(15, 59),
        )?.key,
        'A@2026-10-12',
      );
      expect(
        nextAdminSlot(enabled, today: d('2026-10-12'), nowMinutes: at(16))?.key,
        'B@2026-10-14',
      );
    });

    test('a skipped occurrence is jumped over', () {
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'B',
          originalDate: d('2026-10-14'),
          skipped: true,
        ),
      );
      final next = nextAdminSlot(
        config,
        today: d('2026-10-13'),
        nowMinutes: at(9),
      );
      expect(next?.key, 'C@2026-10-18');
      expect(adminSlotsBetween(config, d('2026-10-12'), 7).map((s) => s.key), [
        'A@2026-10-12',
        'C@2026-10-18',
      ]);
    });

    test('a moved occurrence keeps its identity and new time', () {
      // B moved from Wednesday 14 to Thursday 15 at 09:00 for 30 minutes.
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'B',
          originalDate: d('2026-10-14'),
          date: d('2026-10-15'),
          startMinutes: at(9),
          durationMinutes: 30,
        ),
      );
      final next = nextAdminSlot(
        config,
        today: d('2026-10-13'),
        nowMinutes: at(12),
      )!;
      expect(next.key, 'B@2026-10-14');
      expect(next.date, d('2026-10-15'));
      expect(next.start, DateTime(2026, 10, 15, 9));
      expect(next.end, DateTime(2026, 10, 15, 9, 30));
      expect(next.moved, isTrue);
      // On Thursday after 09:00 the moved slot has started: C is next.
      expect(
        nextAdminSlot(
          config,
          today: d('2026-10-15'),
          nowMinutes: at(9, 1),
        )?.key,
        'C@2026-10-18',
      );
    });

    test('an occurrence moved earlier than another keeps the order', () {
      // C (Sunday 18) moved to Tuesday 13 evening: it comes before B.
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'C',
          originalDate: d('2026-10-18'),
          date: d('2026-10-13'),
          startMinutes: at(18),
        ),
      );
      final next = nextAdminSlot(
        config,
        today: d('2026-10-13'),
        nowMinutes: at(10),
      )!;
      expect(next.key, 'C@2026-10-18');
      expect(
        nextAdminSlot(
          config,
          today: d('2026-10-13'),
          nowMinutes: 0,
          after: next,
        )?.key,
        'B@2026-10-14',
      );
      // Its original Sunday no longer has a slot.
      expect(adminSlotsBetween(config, d('2026-10-18'), 1), isEmpty);
    });

    test('an occurrence moved into the range from outside is listed', () {
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'A',
          originalDate: d('2026-10-19'),
          date: d('2026-10-17'),
        ),
      );
      expect(
        adminSlotsBetween(config, d('2026-10-17'), 1).single.key,
        'A@2026-10-19',
      );
    });

    test('next after a session follows moves and skips', () {
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'B',
          originalDate: d('2026-10-14'),
          skipped: true,
        ),
      );
      final a = adminSlotsBetween(config, d('2026-10-12'), 1).single;
      expect(
        nextAdminSlot(
          config,
          today: d('2026-10-12'),
          nowMinutes: 0,
          after: a,
        )?.key,
        'C@2026-10-18',
      );
    });

    test('daylight saving: wall-clock time stays, length stays', () {
      // Europe/London and the EU end DST on Sunday 25 October 2026 and start
      // it on Sunday 28 March 2027: the Sunday slot is still 17:30-18:25.
      for (final sunday in ['2026-10-25', '2027-03-28']) {
        final slot = nextAdminSlot(
          enabled,
          today: d(sunday).addDays(-1),
          nowMinutes: at(23, 30),
        )!;
        expect(slot.key, 'C@$sunday');
        expect(slot.start.hour, 17);
        expect(slot.start.minute, 30);
        expect(slot.end.difference(slot.start), const Duration(minutes: 55));
      }
      // Twenty weekly Mondays across the change: always 16:00.
      final mondays = adminSlotsBetween(
        enabled,
        d('2026-10-01'),
        140,
      ).where((s) => s.seriesId == 'A');
      expect(mondays.length, 20);
      expect(mondays.every((s) => s.start.hour == 16), isTrue);
    });

    test('no slot for ten weeks: none', () {
      const empty = AdminSessionsConfig(enabled: true, series: []);
      expect(
        nextAdminSlot(empty, today: d('2026-10-12'), nowMinutes: 0),
        isNull,
      );
    });

    test('changing a series drops its future moves only', () {
      final config = enabled
          .withOverride(
            AdminSlotOverride(
              seriesId: 'A',
              originalDate: d('2026-10-05'),
              skipped: true,
            ),
          )
          .withOverride(
            AdminSlotOverride(
              seriesId: 'A',
              originalDate: d('2026-10-19'),
              skipped: true,
            ),
          );
      final changed = config.withSeries(
        config.seriesById('A')!.copyWith(weekday: DateTime.tuesday),
        d('2026-10-13'),
      );
      expect(changed.overrides.map((o) => o.key), ['A@2026-10-05']);
      expect(
        nextAdminSlot(changed, today: d('2026-10-13'), nowMinutes: 0)?.key,
        'A@2026-10-13',
      );
    });

    test('current or last slot for «Chiudi sessione»', () {
      // Monday 16:10, A in progress.
      expect(
        currentOrLastAdminSlot(
          enabled,
          today: d('2026-10-12'),
          nowMinutes: at(16, 10),
        )?.key,
        'A@2026-10-12',
      );
      // Tuesday: A is the last one started.
      expect(
        currentOrLastAdminSlot(
          enabled,
          today: d('2026-10-13'),
          nowMinutes: at(9),
        )?.key,
        'A@2026-10-12',
      );
    });

    test('config survives encoding; garbage falls back to off', () {
      final config = enabled
          .withOverride(
            AdminSlotOverride(
              seriesId: 'B',
              originalDate: d('2026-10-14'),
              date: d('2026-10-15'),
              startMinutes: 540,
            ),
          )
          .closing('A@2026-10-12', d('2026-10-13'))
          .copyWith(minutesPerTask: 15);
      final decoded = AdminSessionsConfig.decode(config.encode());
      expect(decoded.encode(), config.encode());
      expect(decoded.isClosed('A@2026-10-12'), isTrue);
      expect(AdminSessionsConfig.decode('{').enabled, isFalse);
      expect(AdminSessionsConfig.decode(null).series.length, 3);
    });
  });

  group('deferral', () {
    final next = nextAdminSlot(
      enabled,
      today: d('2026-10-13'),
      nowMinutes: at(9),
    );

    test('undated, today and overdue tasks go to the next slot', () {
      for (final date in [null, '2026-10-13', '2026-10-01']) {
        final target = adminDeferTarget(
          showDate: date,
          today: d('2026-10-13'),
          next: next,
        );
        expect(target.outcome, AdminDeferOutcome.slot);
        expect(target.date, d('2026-10-14'));
      }
    });

    test('a specific date before the next slot is kept', () {
      final config = enabled.withOverride(
        AdminSlotOverride(
          seriesId: 'B',
          originalDate: d('2026-10-14'),
          skipped: true,
        ),
      );
      final slot = nextAdminSlot(
        config,
        today: d('2026-10-13'),
        nowMinutes: at(9),
      );
      final target = adminDeferTarget(
        showDate: '2026-10-16',
        today: d('2026-10-13'),
        next: slot,
      );
      expect(target.outcome, AdminDeferOutcome.keepDate);
      expect(target.date, d('2026-10-16'));
    });

    test('a date after the slot is brought to the slot', () {
      final target = adminDeferTarget(
        showDate: '2026-11-30',
        today: d('2026-10-13'),
        next: next,
      );
      expect(target.outcome, AdminDeferOutcome.slot);
      expect(target.date, d('2026-10-14'));
    });

    test('without slots nothing changes', () {
      expect(
        adminDeferTarget(
          showDate: null,
          today: d('2026-10-13'),
          next: null,
        ).outcome,
        AdminDeferOutcome.noSlot,
      );
    });
  });

  group('closing a session', () {
    final slot = adminSlotsBetween(enabled, d('2026-10-12'), 1).single;
    AdminQueueItem item(String id, String status, String? date) =>
        (id: id, status: status, showDate: date);

    test('residue: open items dated on the session day or earlier', () {
      final queue = [
        item('today', 'available', '2026-10-12'),
        item('overdue', 'available', '2026-10-05'),
        item('undated', 'inbox', null),
        item('later', 'scheduled', '2026-10-13'),
        item('waiting', 'waiting', '2026-10-12'),
        item('done', 'completed', '2026-10-12'),
      ];
      expect(adminSessionResidue(queue, slot), ['today', 'overdue']);
      expect(adminTasksOnDate(queue, d('2026-10-12')), ['today']);
    });

    test('queue summary counts, waiting apart, without targets', () {
      final summary = adminQueueSummary([
        item('a', 'available', null),
        item('b', 'scheduled', '2026-10-14'),
        item('w', 'waiting', '2026-10-20'),
        item('c', 'completed', null),
      ], enabled);
      expect(summary.open, 2);
      expect(summary.waiting, 1);
      expect(summary.estimatedMinutes, 20);
    });
  });

  test('fixed ids and sources', () {
    expect(adminProjectId(), adminProjectId());
    expect(
      AdminSection.values.map(adminSectionId).toSet().length,
      AdminSection.values.length,
    );
    expect(AdminSource.fromStored('admin:gmail_opuk'), AdminSource.gmailOpuk);
    expect(canSetAdminSource('todoist'), isFalse);
    expect(canSetAdminSource(null), isTrue);
    expect(canSetAdminSource('admin:semble'), isTrue);
  });
}
