import 'package:deterministic_todo/domain/semble_time.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'London digits and instants agree in summer, winter and both changes',
    () {
      // Summer (BST, UTC+1) and winter (GMT).
      expect(
        londonWallClock(DateTime.utc(2026, 7, 1, 10)),
        DateTime.utc(2026, 7, 1, 9),
      );
      expect(
        londonWallClock(DateTime.utc(2026, 1, 15, 10)),
        DateTime.utc(2026, 1, 15, 10),
      );
      // 29 March 2026: 01:00 GMT becomes 02:00 BST. The skipped hour reads
      // as GMT, the next one as BST.
      expect(
        londonWallClock(DateTime.utc(2026, 3, 29, 0, 30)),
        DateTime.utc(2026, 3, 29, 0, 30),
      );
      expect(
        londonWallClock(DateTime.utc(2026, 3, 29, 1, 30)),
        DateTime.utc(2026, 3, 29, 1, 30),
      );
      expect(
        londonWallClock(DateTime.utc(2026, 3, 29, 2, 30)),
        DateTime.utc(2026, 3, 29, 1, 30),
      );
      // 25 October 2026: 01:30 happens twice; the first (BST) is taken.
      expect(
        londonWallClock(DateTime.utc(2026, 10, 25, 1, 30)),
        DateTime.utc(2026, 10, 25, 0, 30),
      );
      expect(
        londonWallClock(DateTime.utc(2026, 10, 25, 3)),
        DateTime.utc(2026, 10, 25, 3),
      );
      expect(londonSummerTime(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      expect(londonSummerTime(DateTime.utc(2026, 10, 25, 1)), isFalse);
      expect(londonSummerTime(DateTime.utc(2026, 3, 29, 1)), isTrue);
      // The inverse.
      for (final instant in [
        DateTime.utc(2026, 7, 1, 9),
        DateTime.utc(2026, 1, 15, 10),
        DateTime.utc(2026, 3, 29, 1, 30),
        DateTime.utc(2026, 10, 25, 3),
      ]) {
        expect(londonWallClock(londonDigitsOf(instant)), instant);
      }
    },
  );

  test('a block is one London day, with 24:00 as the only next-day end', () {
    expect(
      sembleBlockFor(DateTime.utc(2026, 7, 1, 9), DateTime.utc(2026, 7, 1, 10)),
      (date: const CivilDate(2026, 7, 1), startTime: '10:00', endTime: '11:00'),
    );
    expect(
      sembleBlockFor(
        DateTime.utc(2026, 7, 1, 22),
        DateTime.utc(2026, 7, 1, 23),
      ),
      (date: const CivilDate(2026, 7, 1), startTime: '23:00', endTime: '24:00'),
    );
    expect(
      sembleBlockFor(
        DateTime.utc(2026, 7, 1, 22, 30),
        DateTime.utc(2026, 7, 1, 23, 30),
      ),
      isNull,
    );
    expect(
      sembleBlockFor(DateTime.utc(2026, 7, 1, 9), DateTime.utc(2026, 7, 1, 9)),
      isNull,
    );
  });
}
