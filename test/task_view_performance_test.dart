import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final count in [100, 1000, 10000]) {
    test('bounded visible query with $count synthetic tasks', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TaskRepository(db, deviceId: 'benchmark');
      await db.batch(
        (batch) => batch.insertAll(db.tasks, [
          for (var i = 0; i < count; i++)
            TasksCompanion.insert(
              id: 'fixture-$i',
              title: 'Synthetic $i',
              notes: Value('x' * 1000),
              status: 'scheduled',
              showDate: Value(i < 10 ? '2026-09-12' : '2027-09-12'),
              position: i,
              createdAt: i,
              updatedAt: i,
              deviceId: 'benchmark',
            ),
        ]),
      );
      final timer = Stopwatch()..start();
      final visible = await repo
          .watchView(
            view: 'upcoming',
            today: '2026-09-11',
            fromDate: '2026-09-12',
            throughDate: '2026-10-11',
          )
          .first;
      timer.stop();
      expect(visible, hasLength(10));
      expect(
        await repo.watchView(view: 'projects', today: '2026-09-11').first,
        isEmpty,
      );
      // Technical measurements only; this is a host SQLite benchmark, not frame/RAM evidence.
      // ignore: avoid_print
      print(
        'todo_query fixture_rows=$count visible_rows=${visible.length} query_us=${timer.elapsedMicroseconds}',
      );
    });
  }
}
