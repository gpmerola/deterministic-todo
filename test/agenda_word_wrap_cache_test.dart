import 'package:deterministic_todo/ui/views/agenda_word_wrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = TextStyle(fontSize: 12, height: 1.2);
  const scaler = TextScaler.noScaling;

  setUp(clearWrapWordsCache);

  test('cached lines equal a fresh measurement', () {
    const title = 'Synthetic event 12 with a fairly long title';
    final first = wrapWords(title, style, 60, scaler);
    final again = wrapWords(title, style, 60, scaler);
    expect(identical(first, again), isTrue);
    clearWrapWordsCache();
    expect(wrapWords(title, style, 60, scaler), first);
  });

  test('width, style and scale are part of the key', () {
    const title = 'Weekly team meeting room booking';
    final narrow = wrapWords(title, style, 40, scaler);
    final wide = wrapWords(title, style, 400, scaler);
    expect(wide, hasLength(1));
    expect(narrow.length, greaterThan(1));
    final scaled = wrapWords(title, style, 400, const TextScaler.linear(3));
    expect(scaled.length, greaterThan(1));
    final bigger = wrapWords(title, style.copyWith(fontSize: 40), 400, scaler);
    expect(bigger.length, greaterThan(1));
    expect(wrapCacheLength, 4);
  });

  test('cached lines cannot be changed by a caller', () {
    final lines = wrapWords('One two', style, 400, scaler);
    expect(() => lines.add('three'), throwsUnsupportedError);
  });

  test('the cache stays bounded and keeps recent entries', () {
    final keep = wrapWords('kept title', style, 100, scaler);
    for (var index = 0; index < wrapCacheCapacity + 10; index++) {
      wrapWords('title $index', style, 100, scaler);
      if (index % 100 == 0) wrapWords('kept title', style, 100, scaler);
    }
    expect(wrapCacheLength, wrapCacheCapacity);
    expect(
      identical(wrapWords('kept title', style, 100, scaler), keep),
      isTrue,
    );
  });
}
