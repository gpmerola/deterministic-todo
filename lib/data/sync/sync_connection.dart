import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/diagnostic_log_service.dart';

/// State of the Realtime channel shown as «Live» in the interface.
enum RealtimeLink { connected, connecting, disconnected }

/// Transport lifecycle only. It never reads or writes Todo rows or outbox.
class SyncConnection {
  SyncConnection(
    this.client, {
    required this.isActive,
    required this.onAuth,
    required this.onOffline,
    required this.onOnline,
    required this.onSubscribed,
    required this.onRecord,
    Duration Function()? retryDelay,
  }) : retryDelay = retryDelay ?? (() => const Duration(seconds: 2));
  final SupabaseClient client;
  final bool Function() isActive;

  /// Pause before re-joining a channel that closed or failed.
  final Duration Function() retryDelay;
  final void Function(AuthState) onAuth;
  final void Function() onOffline, onOnline, onSubscribed;
  final void Function(String, PostgresChangePayload) onRecord;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  RealtimeChannel? _channel;
  Timer? _retry;
  bool _disposed = false;
  final _link = ValueNotifier(RealtimeLink.disconnected);

  /// Changes only on channel events: no timer or polling of its own.
  ValueListenable<RealtimeLink> get link => _link;

  void _setLink(RealtimeLink value) => _link.value = value;

  void start() {
    _auth ??= client.auth.onAuthStateChange.listen(onAuth);
    _connectivity ??= Connectivity().onConnectivityChanged.listen((result) {
      if (_disposed) return;
      if (result.contains(ConnectivityResult.none)) {
        onOffline();
      } else if (isActive()) {
        onOnline();
      }
    });
  }

  Future<void> subscribe() async {
    if (_disposed || !isActive() || _channel != null) return;
    final user = client.auth.currentUser;
    if (user == null) return;
    final channel = client.channel('todo-live-${user.id}');
    for (final table in const ['tasks', 'projects', 'project_sections']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (payload) => onRecord(table, payload),
      );
    }
    _channel = channel;
    _setLink(RealtimeLink.connecting);
    channel.subscribe((status, error) => unawaited(_status(channel, status)));
  }

  Future<void> _status(
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
  ) async {
    if (_disposed || !identical(channel, _channel)) return;
    final reconnect = status != RealtimeSubscribeStatus.subscribed;
    unawaited(
      DiagnosticLogService.instance.event(
        'realtime_status',
        level: reconnect ? 'warning' : 'info',
        fields: {'status': status.name},
      ),
    );
    if (!reconnect) {
      _retry?.cancel();
      _retry = null;
      _setLink(RealtimeLink.connected);
      if (isActive()) onSubscribed();
      return;
    }
    _channel = null;
    _setLink(RealtimeLink.disconnected);
    try {
      await client.removeChannel(channel);
    } on Object {
      /* Retry independently. */
    }
    if (_disposed || !isActive() || client.auth.currentUser == null) return;
    _retry?.cancel();
    _retry = Timer(retryDelay(), () {
      _retry = null;
      unawaited(subscribe());
    });
  }

  Future<void> disconnect() async {
    _retry?.cancel();
    _retry = null;
    final channel = _channel;
    _channel = null;
    _setLink(RealtimeLink.disconnected);
    if (channel != null) await client.removeChannel(channel);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _connectivity?.cancel();
    await _auth?.cancel();
    await disconnect();
    // [link] is not disposed: widgets may still detach from it afterwards.
  }
}
