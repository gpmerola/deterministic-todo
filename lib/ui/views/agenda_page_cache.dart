import 'package:flutter/foundation.dart';

/// Bounded page state shared by month, week and multi-week calendars.
/// Eviction/invalidation also detaches pending reads: their late results cannot
/// repopulate the cache or replace a newer revision.
class AgendaPageCache<T> extends ChangeNotifier {
  AgendaPageCache({this.capacity = 7}) : assert(capacity > 1);
  final int capacity;
  final _pages = <int, _Page<T>>{};
  int? _visible;
  bool _disposed = false;

  int get length => _pages.length;
  bool contains(int page) => _pages.containsKey(page);
  bool loading(int page) => _pages[page]?.pending != null;
  bool failed(int page) => _pages[page]?.failed ?? false;
  bool needsLoad(int page) {
    final entry = _pages[page];
    return entry == null ||
        (!entry.failed && entry.pending == null && entry.stale);
  }

  void focus(int page) => _visible = page;

  _Page<T> _entry(int page) {
    final entry = _pages.remove(page) ?? _Page<T>();
    _pages[page] = entry;
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.firstWhere((key) => key != _visible));
    }
    return entry;
  }

  /// A synchronous preview must not notify while the widget is building.
  T? read(int page, T? Function() peek) {
    final entry = _entry(page);
    if (entry.data == null) {
      entry.data = peek();
      // A preview is not proof that this revision has been loaded.
    }
    return entry.data;
  }

  Future<void> load(int page, Future<T> Function() fetch) {
    if (_disposed) return Future.value();
    final entry = _entry(page);
    if (entry.pending != null) return entry.pending!;
    if (!entry.stale || entry.failed) return Future.value();
    return entry.pending = _load(page, entry, fetch);
  }

  Future<void> retry(int page, Future<T> Function() fetch) {
    if (_disposed) return Future.value();
    final entry = _entry(page);
    if (entry.pending != null) return entry.pending!;
    entry.failed = false;
    entry.stale = true;
    final work = load(page, fetch);
    notifyListeners();
    return work;
  }

  Future<void> _load(
    int page,
    _Page<T> entry,
    Future<T> Function() fetch,
  ) async {
    try {
      final result = await fetch();
      if (_disposed || !identical(_pages[page], entry)) return;
      entry.data = result;
      entry.stale = false;
    } catch (_) {
      if (_disposed || !identical(_pages[page], entry)) return;
      entry.failed = true;
    } finally {
      entry.pending = null;
      if (!_disposed && identical(_pages[page], entry)) notifyListeners();
    }
  }

  /// Keep old content during a revision refresh, clear it when dates/layout
  /// change. Replacing entries isolates callbacks from the previous generation.
  void invalidate({bool clear = false}) {
    if (clear) {
      _pages.clear();
    } else {
      for (final key in _pages.keys.toList()) {
        _pages[key] = _Page<T>()..data = _pages[key]!.data;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pages.clear();
    super.dispose();
  }
}

class _Page<T> {
  T? data;
  bool stale = true;
  bool failed = false;
  Future<void>? pending;
}
