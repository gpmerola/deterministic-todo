import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

final class SyncCancelled implements Exception {
  const SyncCancelled();
}

/// One account/lifecycle generation. Aborts transport, never discards intents.
class SyncRequestScope {
  SyncRequestScope(this.client, {this.timeout = const Duration(seconds: 20)})
    : userId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? userId;
  final Duration timeout;
  final _abort = Completer<void>();

  bool get isActive =>
      !_abort.isCompleted && userId == client.auth.currentUser?.id;

  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
  }

  void check() {
    if (!isActive) throw const SyncCancelled();
  }

  Future<T> send<T>(PostgrestBuilder<T, dynamic, dynamic> request) async {
    check();
    final result = await request
        .retry(enabled: false, requestTimeout: timeout)
        .abortSignal(_abort.future);
    check();
    return result;
  }
}
