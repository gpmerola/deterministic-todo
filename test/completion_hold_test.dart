import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/ui/completion_hold.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build 271: a completion is written at the tap and lists keep the row,
/// as it was, until its animation ends.
void main() {
  late AppDatabase db;
  late TaskRepository repository;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(db, deviceId: 'synthetic');
  });
  tearDown(() => db.close());

  Future<List<Task>> tasks() => db.select(db.tasks).get();

  test('a held task stays at its place until released', () async {
    for (final title in ['A', 'B', 'C']) {
      await repository.create(title);
    }
    final rows = await tasks();
    final source = StreamController<List<Task>>();
    final hold = CompletionHold.of(repository);
    final seen = <List<String>>[];
    final subscription = hold
        .keep(source.stream)
        .listen((list) => seen.add([for (final t in list) t.title]));
    source.add(rows);
    await pumpEventQueue();
    hold.hold(rows[1]);
    source.add([rows[0], rows[2]]);
    await pumpEventQueue();
    hold.release(rows[1].id);
    await pumpEventQueue();
    expect(seen, [
      ['A', 'B', 'C'],
      ['A', 'B', 'C'],
      ['A', 'B', 'C'],
      ['A', 'C'],
    ]);
    await subscription.cancel();
    await source.close();
  });

  test('a held task never enters a list that did not show it', () async {
    await repository.create('A');
    await repository.create('Altrove');
    final held = (await tasks()).last;
    final source = StreamController<List<Task>>();
    final hold = CompletionHold.of(repository)..hold(held);
    final seen = <List<String>>[];
    final subscription = hold
        .keep(source.stream)
        .listen((list) => seen.add([for (final t in list) t.title]));
    source.add([(await tasks()).first]);
    await pumpEventQueue();
    hold.release(held.id);
    await pumpEventQueue();
    expect(seen.every((titles) => !titles.contains('Altrove')), isTrue);
    await subscription.cancel();
    await source.close();
  });
}
