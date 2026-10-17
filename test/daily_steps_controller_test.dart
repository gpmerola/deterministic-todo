import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/services/run_tracker_service.dart';
import 'package:deterministic_todo/ui/shell/daily_steps_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DailyMovementProgress? progress;
  late int goal;
  late int goalReads;
  late int celebrations;
  late int notifications;
  late DailyStepsController controller;

  DailyStepsController create() => DailyStepsController(
    database: db,
    onGoalReached: () => celebrations++,
    readProgress: () async => progress,
    readGoal: () async {
      goalReads++;
      return goal;
    },
    writeGoal: (value) async => goal = value,
  )..addListener(() => notifications++);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    progress = const DailyMovementProgress(day: '2026-10-07', steps: 4000);
    goal = 10000;
    goalReads = 0;
    celebrations = 0;
    notifications = 0;
    controller = create();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('passi invariati non notificano la shell', () async {
    await controller.refresh();
    expect(notifications, 1);
    await controller.refresh(full: false);
    await controller.refresh(full: false);
    expect(notifications, 1);

    progress = const DailyMovementProgress(day: '2026-10-07', steps: 4100);
    await controller.refresh(full: false);
    expect(notifications, 2);
    expect(controller.progress?.steps, 4100);
  });

  test('il tick periodico non rilegge obiettivo e preferenze', () async {
    await controller.refresh();
    await controller.refresh(full: false);
    expect(goalReads, 1);
    await controller.refresh();
    expect(goalReads, 2);
  });

  test('celebra una sola volta al giorno, anche dopo un riavvio', () async {
    progress = const DailyMovementProgress(day: '2026-10-07', steps: 10000);
    await controller.refresh();
    await controller.refresh();
    expect(celebrations, 1);

    controller.dispose();
    controller = create();
    await controller.refresh();
    expect(celebrations, 1);

    progress = const DailyMovementProgress(day: '2026-10-08', steps: 12000);
    await controller.refresh(full: false);
    expect(celebrations, 2);
  });

  test(
    'alzare l obiettivo sopra i passi consente una nuova celebrazione',
    () async {
      progress = const DailyMovementProgress(day: '2026-10-07', steps: 10000);
      await controller.refresh();
      expect(celebrations, 1);

      await controller.setGoal(12000);
      expect(controller.goal, 12000);
      progress = const DailyMovementProgress(day: '2026-10-07', steps: 12000);
      await controller.refresh(full: false);
      expect(celebrations, 2);
    },
  );
}
