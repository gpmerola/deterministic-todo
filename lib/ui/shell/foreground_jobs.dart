import 'dart:async';

/// Independent foreground work. One lease per job, including after a timeout:
/// timing out a Future cannot cancel its underlying IO or make a retry safe.
class ForegroundJobs {
  ForegroundJobs({required this.onFailure});
  final void Function(String job, Object error) onFailure;
  final Map<String, Future<void>> _running = {};
  bool _disposed = false;

  Future<void> run(
    String name,
    Future<void> Function() action, {
    Duration? timeout = const Duration(seconds: 30),
  }) {
    if (_disposed) return Future.value();
    final existing = _running[name];
    if (existing != null) return existing;
    final work = Future<void>.sync(action);
    // Keep the lease until the underlying operation really ends. Observe late
    // errors as well, without letting one job break unrelated foreground work.
    final settled = work.then<void>(
      (_) {
        _running.remove(name);
      },
      onError: (Object error, StackTrace stack) {
        _running.remove(name);
        _report(name, error);
      },
    );
    final observed = timeout == null
        ? settled
        : settled.timeout(
            timeout,
            onTimeout: () {
              _report(name, TimeoutException('Foreground job deadline'));
            },
          );
    _running[name] = observed;
    return observed;
  }

  void _report(String name, Object error) {
    if (_disposed) return;
    try {
      onFailure(name, error);
    } catch (_) {
      // Diagnostics cannot affect the operation being observed.
    }
  }

  void dispose() {
    _disposed = true;
  }
}
