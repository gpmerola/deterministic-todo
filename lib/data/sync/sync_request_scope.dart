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

  int requestCount = 0;
  int networkMs = 0;
  int comparisonMs = 0;
  int purgeMs = 0;

  Future<T> compareLocally<T>(Future<T> Function() body) async {
    final timer = Stopwatch()..start();
    try {
      return await body();
    } finally {
      comparisonMs += timer.elapsedMilliseconds;
    }
  }

  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
  }

  void check() {
    if (!isActive) throw const SyncCancelled();
  }

  Future<T> send<T>(PostgrestBuilder<T, dynamic, dynamic> request) async {
    check();
    requestCount++;
    final timer = Stopwatch()..start();
    try {
      final result = await request
          .retry(enabled: false, requestTimeout: timeout)
          .abortSignal(_abort.future);
      check();
      return result;
    } finally {
      networkMs += timer.elapsedMilliseconds;
    }
  }
}
