import 'dart:async';

import 'package:deterministic_todo/ui/views/agenda_page_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit retry keeps old data and joins repeated taps', () async {
    final cache = AgendaPageCache<int>();
    addTearDown(cache.dispose);
    await cache.load(0, () async => 10);
    cache.invalidate();
    await cache.load(0, () async => throw StateError('synthetic'));
    final pending = Completer<int>();
    var calls = 0;
    final first = cache.retry(0, () {
      calls++;
      return pending.future;
    });
    final second = cache.retry(0, () async {
      calls++;
      return 30;
    });
    expect(cache.read(0, () => null), 10);
    expect(calls, 1);
    pending.complete(20);
    await Future.wait([first, second]);
    expect(cache.read(0, () => null), 20);
  });

  test(
    'hundreds of visited pages stay bounded and visible page survives',
    () async {
      final cache = AgendaPageCache<int>();
      addTearDown(cache.dispose);
      cache.focus(0);
      await cache.load(0, () async => 0);
      for (var i = 1; i <= 300; i++) {
        await cache.load(i, () async => i);
        expect(cache.length, lessThanOrEqualTo(7));
      }
      expect(cache.contains(0), isTrue);
      expect(cache.contains(1), isFalse);
      expect(cache.read(300, () => null), 300);
    },
  );

  test('coalesces reads; evicted pending result cannot return', () async {
    final cache = AgendaPageCache<int>(capacity: 2);
    addTearDown(cache.dispose);
    final pending = Completer<int>();
    var calls = 0;
    final first = cache.load(0, () {
      calls++;
      return pending.future;
    });
    final duplicate = cache.load(0, () async {
      calls++;
      return 99;
    });
    expect(identical(first, duplicate), isTrue);
    await cache.load(1, () async => 1);
    await cache.load(2, () async => 2);
    pending.complete(0);
    await first;
    expect(calls, 1);
    expect(cache.contains(0), isFalse);
    expect(cache.length, 2);
  });

  test(
    'refresh keeps preview, rejects old completion and retries error',
    () async {
      final cache = AgendaPageCache<int>();
      addTearDown(cache.dispose);
      await cache.load(0, () async => 10);
      cache.invalidate();
      expect(cache.read(0, () => null), 10);
      final old = Completer<int>();
      final oldLoad = cache.load(0, () => old.future);
      cache.invalidate();
      await cache.load(0, () async => 20);
      old.complete(11);
      await oldLoad;
      expect(cache.read(0, () => null), 20);
      cache.invalidate();
      await cache.load(0, () async => throw StateError('synthetic'));
      expect(cache.failed(0), isTrue);
      expect(cache.needsLoad(0), isFalse);
      expect(cache.read(0, () => null), 20);
      cache.invalidate();
      await cache.load(0, () async => 30);
      expect(cache.failed(0), isFalse);
      cache.invalidate(clear: true);
      expect(cache.length, 0);
    },
  );

  test(
    'preview is refreshed and late completion after disposal is ignored',
    () async {
      final cache = AgendaPageCache<int>();
      var notifications = 0;
      cache.addListener(() => notifications++);
      expect(cache.read(1, () => 10), 10);
      expect(cache.needsLoad(1), isTrue);
      final pending = Completer<int>();
      final work = cache.load(1, () => pending.future);
      cache.dispose();
      pending.complete(11);
      await work;
      expect(notifications, 0);
      expect(cache.length, 0);
    },
  );
}
