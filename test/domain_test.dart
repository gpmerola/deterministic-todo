import 'package:deterministic_todo/domain/recurrence.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date civili e ricorrenze', () {
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
