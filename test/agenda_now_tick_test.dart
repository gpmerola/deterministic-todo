import 'package:deterministic_todo/ui/views/agenda_now_tick.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingGrid extends StatelessWidget {
  const _CountingGrid(this.builds);
  final List<int> builds;
  @override
  Widget build(BuildContext context) {
    builds[0]++;
    return const SizedBox.expand();
  }
}

void main() {
  testWidgets('the now line follows the minute, pauses in background and '
      'jumps to the current time on resume', (tester) async {
    var clock = DateTime(2026, 10, 19, 10, 0, 30);
    final grid = [0];
    double top() =>
        tester.widget<Positioned>(find.byKey(const ValueKey('now'))).top!;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            _CountingGrid(grid),
            AgendaNowTick(
              now: () => clock,
              builder: (context, now) => Positioned(
                key: const ValueKey('now'),
                top: (now.hour * 60 + now.minute).toDouble(),
                left: 0,
                right: 0,
                child: const SizedBox(height: 2),
              ),
            ),
          ],
        ),
      ),
    );
    expect(top(), 600);
    expect(grid[0], 1);

    // Next minute boundary: only the line rebuilds.
    clock = DateTime(2026, 10, 19, 10, 1, 0, 60);
    await tester.pump(const Duration(seconds: 31));
    expect(top(), 601);
    expect(grid[0], 1);

    // Screen locked for half an hour: no timer runs in background.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = DateTime(2026, 10, 19, 10, 31, 20);
    await tester.pump(const Duration(minutes: 30));
    expect(top(), 601);

    // Unlock: the line is right at once, before any timer.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(top(), 631);
    expect(grid[0], 1);

    // A transient `inactive` (system dialog) neither stops nor restarts it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    clock = DateTime(2026, 10, 19, 10, 32, 0, 60);
    await tester.pump(const Duration(seconds: 41));
    expect(top(), 632);
  });
}
