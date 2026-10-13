import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/local/database.dart';
import '../data/task_repository.dart';

/// Tasks completed from a list while their check-and-collapse animation
/// runs (build 271). The completion is written to SQLite at the tap, so
/// quitting the browser or the app right after it keeps it; lists passed
/// through [keep] go on showing the row as it was until [release], so the
/// animation is the same as when the write waited for it.
class CompletionHold extends ChangeNotifier {
  CompletionHold._();

  static final _holds = Expando<CompletionHold>();

  /// One hold per repository, shared by every list showing its tasks.
  static CompletionHold of(TaskRepository repository) =>
      _holds[repository] ??= CompletionHold._();

  final _held = <String, Task>{};

  /// Keeps [task], as shown before completing it, in the lists that show it.
  void hold(Task task) {
    _held[task.id] = task;
    notifyListeners();
  }

  void release(String id) {
    if (_held.remove(id) != null) notifyListeners();
  }

  /// [source] with every held task that this stream showed before put back
  /// at its previous position. A held task never enters a list that did not
  /// show it.
  Stream<List<Task>> keep(Stream<List<Task>> source) =>
      Stream<List<Task>>.multi((controller) {
        List<Task>? latest;
        var shown = const <Task>[];
        void emit() {
          final rows = latest;
          if (rows == null) return;
          final merged = List<Task>.of(rows);
          if (_held.isNotEmpty) {
            final ids = {for (final task in rows) task.id};
            for (final (index, task) in shown.indexed) {
              final held = _held[task.id];
              if (held != null && !ids.contains(task.id)) {
                merged.insert(index.clamp(0, merged.length), held);
              }
            }
          }
          shown = merged;
          controller.add(merged);
        }

        addListener(emit);
        final subscription = source.listen(
          (rows) {
            latest = rows;
            emit();
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = () {
          removeListener(emit);
          return subscription.cancel();
        };
      });
}
