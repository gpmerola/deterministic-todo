import 'dart:async';

import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/ui/event_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('typing ten characters makes one provider request', (
    tester,
  ) async {
    final queries = <String>[];
    final controller = EventSearchController((query) async {
      queries.add(query);
      return [];
    });
    addTearDown(controller.dispose);
    for (var i = 2; i <= 11; i++) {
      controller.setQuery('abcdefghijk'.substring(0, i));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(queries, isEmpty);
    await tester.pump(EventSearchController.delay);
    expect(queries, ['abcdefghijk']);
    expect(controller.loading, isFalse);
  });

  testWidgets(
    'slow request never queues intermediate queries or stale errors',
    (tester) async {
      final first = Completer<List<AgendaEntry>>();
      final queries = <String>[];
      final controller = EventSearchController((query) {
        queries.add(query);
        return query == 'first' ? first.future : Future.value([]);
      });
      addTearDown(controller.dispose);
      controller.setQuery('first');
      await tester.pump(EventSearchController.delay);
      controller.setQuery('intermediate');
      await tester.pump(EventSearchController.delay);
      controller.setQuery('latest');
      await tester.pump(EventSearchController.delay);
      expect(queries, ['first']);
      first.completeError(StateError('synthetic'));
      await tester.pump();
      expect(queries, ['first', 'latest']);
      expect(controller.failed, isFalse);
      expect(controller.loading, isFalse);
    },
  );

  testWidgets('cache expires, invalidates on resume and is bounded', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 12);
    var reads = 0;
    final controller = EventSearchController((_) async {
      reads++;
      return [];
    }, now: () => now);
    addTearDown(controller.dispose);
    for (final query in ['alpha', 'beta', 'alpha']) {
      controller.setQuery(query);
      await tester.pump(EventSearchController.delay);
    }
    expect(reads, 2);
    now = now.add(const Duration(seconds: 21));
    controller.setQuery('beta');
    await tester.pump(EventSearchController.delay);
    expect(reads, 3);
    controller.invalidate();
    await tester.pump(EventSearchController.delay);
    expect(reads, 4);
    for (var i = 0; i < 9; i++) {
      controller.setQuery('query$i');
      await tester.pump(EventSearchController.delay);
    }
    controller.setQuery('beta');
    await tester.pump(EventSearchController.delay);
    expect(reads, 14);
  });

  testWidgets('short query and closing search cancel pending work', (
    tester,
  ) async {
    var reads = 0;
    final controller = EventSearchController((_) async {
      reads++;
      return [];
    });
    controller.setQuery('alpha');
    controller.setQuery('a');
    await tester.pump(EventSearchController.delay);
    expect(reads, 0);
    controller.setQuery('alpha');
    controller.dispose();
    await tester.pump(EventSearchController.delay);
    expect(reads, 0);
  });
}
