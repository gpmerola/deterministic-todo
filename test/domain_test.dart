import 'package:deterministic_todo/domain/recurrence.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date civili e ricorrenze', () {
    test('descrive le ricorrenze con la frase intelligente', () {
      expect(
        recurrenceSmartLabel('calendar:day:1', '2026-08-04'),
        'ogni giorno',
      );
      expect(
        recurrenceSmartLabel('calendar:week:1', '2026-08-09'),
        'ogni domenica',
      );
      expect(
        recurrenceSmartLabel('calendar:monthWeekday:1', '2026-08-18'),
        'ogni terzo martedì del mese',
      );
      expect(
        recurrenceSmartLabel('calendar:year:1', '2026-07-03'),
        'ogni 3 luglio',
      );
      expect(
        recurrenceSmartLabel('afterCompletion:day:4', '2026-08-04'),
        'ogni 4 giorni dopo il completamento',
      );
    });

    test('il mensile conserva l’ancora dopo febbraio bisestile', () {
      const anchor = CivilDate(2024, 1, 31);
      const rule = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.month,
      );
      final february = nextOccurrence(anchor, anchor, rule);
      final march = nextOccurrence(anchor, february, rule);
      expect(february, const CivilDate(2024, 2, 29));
      expect(march, const CivilDate(2024, 3, 31));
    });

    test('giornaliera attraversa il cambio DST come data civile', () {
      const rule = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      );
      expect(
        nextOccurrence(
          const CivilDate(2026, 3, 28),
          const CivilDate(2026, 3, 28),
          rule,
        ),
        const CivilDate(2026, 3, 29),
      );
    });

    test('il terzo martedì resta tale nel mese successivo', () {
      const rule = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.monthWeekday,
      );
      expect(
        nextOccurrence(
          const CivilDate(2026, 8, 18),
          const CivilDate(2026, 8, 18),
          rule,
        ),
        const CivilDate(2026, 9, 15),
      );
    });

    test('giorni feriali saltano il weekend', () {
      const rule = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.weekday,
      );
      expect(
        nextOccurrence(
          const CivilDate(2026, 8, 7),
          const CivilDate(2026, 8, 7),
          rule,
        ),
        const CivilDate(2026, 8, 10),
      );
    });

    test('ultimo giorno e ultimo venerdì seguono il mese', () {
      expect(
        nextOccurrence(
          const CivilDate(2026, 8, 31),
          const CivilDate(2026, 8, 31),
          const RecurrenceRule(
            type: RecurrenceType.calendar,
            unit: RecurrenceUnit.monthEnd,
          ),
        ),
        const CivilDate(2026, 9, 30),
      );
      expect(
        nextOccurrence(
          const CivilDate(2026, 8, 28),
          const CivilDate(2026, 8, 28),
          const RecurrenceRule(
            type: RecurrenceType.calendar,
            unit: RecurrenceUnit.monthLastWeekday,
          ),
        ),
        const CivilDate(2026, 9, 25),
      );
    });
  });

  test('il conflitto usa deviceId soltanto a parità di contatore', () {
    expect(
      const LogicalVersion(3, 'b').compareTo(const LogicalVersion(3, 'a')),
      1,
    );
    expect(
      const LogicalVersion(4, 'a').compareTo(const LogicalVersion(3, 'z')),
      1,
    );
  });

  test('una serie arretrata conserva tutte le occorrenze', () {
    final dates = calendarOccurrences(
      anchor: const CivilDate(2026, 1, 5),
      through: const CivilDate(2026, 1, 8),
      rule: const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.day,
      ),
    );
    expect(dates, const [
      CivilDate(2026, 1, 5),
      CivilDate(2026, 1, 6),
      CivilDate(2026, 1, 7),
      CivilDate(2026, 1, 8),
    ]);
  });
}
