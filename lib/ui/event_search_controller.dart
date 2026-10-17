import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/agenda.dart';

/// Session-only search. At most one provider read and one latest pending query.
/// Event content is never persisted. Closing search drops its bounded cache.
class EventSearchController extends ChangeNotifier {
  EventSearchController(this.search, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final Future<List<AgendaEntry>> Function(String) search;
  final DateTime Function() now;
  static const delay = Duration(milliseconds: 250);
  static const cacheLifetime = Duration(seconds: 20);
  static const cacheLimit = 8;
  final _cache = <String, (DateTime, List<AgendaEntry>)>{};
  Timer? _timer;
  String _query = '';
  int _generation = 0;
  bool _running = false;
  bool _ready = false;
  bool _disposed = false;
  bool loading = false;
  bool failed = false;
  List<AgendaEntry> results = const [];

  void setQuery(String value, {bool force = false}) {
    final query = value.trim();
    if (_disposed || (!force && query == _query)) return;
    _query = query;
    _generation++;
    _timer?.cancel();
    _ready = false;
    failed = false;
    results = const [];
    loading = query.length >= 2;
    if (loading) {
      final cached = _cache.remove(query);
      if (!force &&
          cached != null &&
          now().difference(cached.$1) >= Duration.zero &&
          now().difference(cached.$1) < cacheLifetime) {
        _cache[query] = cached;
        results = cached.$2;
        loading = false;
      } else {
        _timer = Timer(delay, () {
          _ready = true;
          unawaited(_drain());
        });
      }
    }
    notifyListeners();
  }

  void invalidate() {
    _cache.clear();
    setQuery(_query, force: true);
  }

  Future<void> _drain() async {
    if (_disposed || _running || !_ready) return;
    _running = true;
    _ready = false;
    final generation = _generation;
    final query = _query;
    try {
      final value = List<AgendaEntry>.unmodifiable(await search(query));
      if (_disposed || generation != _generation) return;
      _cache[query] = (now(), value);
      while (_cache.length > cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      results = value;
    } catch (_) {
      if (!_disposed && generation == _generation) failed = true;
    } finally {
      _running = false;
      if (!_disposed) {
        if (generation == _generation) {
          loading = false;
          notifyListeners();
        }
        if (_ready) unawaited(_drain());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cache.clear();
    super.dispose();
  }
}
