import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/ui/shell/civil_day_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notifica una volta a mezzanotte senza polling', (tester) async {
    var now = DateTime(2026, 9, 27, 23, 59, 30);
    final clock = CivilDayClock(now: () => now);
    var notifications = 0;
    clock.addListener(() => notifications++);
    expect(clock.today, const CivilDate(2026, 9, 27));

    now = DateTime(2026, 9, 27, 23, 59, 59);
    await tester.pump(const Duration(seconds: 29));
    expect(notifications, 0);

    now = DateTime(2026, 9, 28, 0, 0, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(clock.today, const CivilDate(2026, 9, 28));
    expect(notifications, 1);

    // Only one timer is pending: the next one is a full day away.
    now = DateTime(2026, 9, 28, 12);
    await tester.pump(const Duration(hours: 12));
    expect(notifications, 1);
    clock.dispose();
  });

  testWidgets('refresh recupera un timer ritardato dalla sospensione', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 27, 22);
    final clock = CivilDayClock(now: () => now);
    now = DateTime(2026, 9, 29, 8);
    clock.refresh();
    expect(clock.today, const CivilDate(2026, 9, 29));
    clock.refresh();
    expect(clock.today, const CivilDate(2026, 9, 29));
    clock.dispose();
  });
}
