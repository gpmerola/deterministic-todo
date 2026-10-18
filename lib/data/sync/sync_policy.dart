import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' show LogicalVersion;
import 'paged_remote.dart';
import 'sync_status.dart';
import 'task_sync_writer.dart';

/// The first steps are short: a check started on resume or on waking often
/// fails once while the radio or Wi-Fi reconnects, and the other device's
/// edit should then appear in seconds. Later steps stay sparse.
Duration syncRetryDelay(int failureIndex) {
  const delays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];
  return delays[failureIndex.clamp(0, delays.length - 1)];
}

int? syncOutboxOldestAgeMs(Iterable<int> createdAtMicros, DateTime now) {
  if (createdAtMicros.isEmpty) return null;
  final oldest = createdAtMicros.reduce(
    (left, right) => left < right ? left : right,
  );
  final age = now.microsecondsSinceEpoch - oldest;
  return age <= 0 ? 0 : age ~/ Duration.microsecondsPerMillisecond;
}

String syncAuthState(Session? session, {DateTime? now}) {
  if (session == null) return 'missing';
  final expiresAt = session.expiresAt;
  if (expiresAt == null) return 'active_unknown_expiry';
  final seconds =
      (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  if (expiresAt <= seconds) return 'expired';
  if (expiresAt - seconds <= 60) return 'near_expiry';
  return 'active';
}

Future<String> safeSyncNetworkState() async {
  try {
    final result = await Connectivity().checkConnectivity();
    if (result.isEmpty || result.contains(ConnectivityResult.none)) {
      return 'none';
    }
    return result.map((item) => item.name).toSet().join('+');
  } on Object {
    return 'unknown';
  }
}

String safeSyncErrorClass(Object error) {
  if (error is SyncPaginationException) return 'pagination';
  if (error is SyncIntentConflictException) return 'intent_conflict';
  if (error is SyncConcurrentWriteException) return 'concurrent_write';
  if (error is SyncWriteVerificationException) return 'write_verification';
  if (error is PostgrestException) return 'supabase';
  if (error is AuthRetryableFetchException) return 'auth_transport';
  if (error is TimeoutException) return 'timeout';
  if (error is http.ClientException) return 'network';
  final type = error.runtimeType.toString().toLowerCase();
  if (type.contains('retryablefetch')) return 'auth_transport';
  if (type.contains('timeout')) return 'timeout';
  if (type.contains('socket') ||
      type.contains('network') ||
      type.contains('connection') ||
      type.contains('handshake') ||
      type.contains('clientexception')) {
    return 'network';
  }
  return 'unexpected';
}

LogicalVersion? announcedVersion(Map<String, dynamic> record) {
  final counter = record['logical_version'];
  final device = record['device_id'];
  return counter is int && device is String
      ? LogicalVersion(counter, device)
      : null;
}

bool outboxOperationsChanged(Set<String> previous, Set<String> current) =>
    previous.length != current.length || !previous.containsAll(current);

/// SQLSTATE classes 22 (data) and 23 (integrity) concern the submitted row.
/// Auth, RLS, schema and transport errors still abort the whole cycle.
bool isEntityRejection(PostgrestException error) {
  final code = error.code;
  return code != null &&
      code.length == 5 &&
      (code.startsWith('22') || code.startsWith('23'));
}

bool isRecurringOccurrenceConflict(PostgrestException error) =>
    error.code == '23505' &&
    error.message.contains('tasks_user_id_series_id_occurrence_key_key');

bool isTransientSyncError(Object error) {
  if (error is http.ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return true;
  }
  if (error is SyncConcurrentWriteException) return true;
  if (error is SyncWriteVerificationException) return true;
  final type = error.runtimeType.toString().toLowerCase();
  if (type.contains('socket') ||
      type.contains('clientexception') ||
      type.contains('timeout') ||
      type.contains('handshake') ||
      type.contains('network') ||
      type.contains('connection') ||
      type.contains('retryablefetch')) {
    return true;
  }
  if (error is PostgrestException) {
    return const {
      'PGRST000',
      'PGRST001',
      'PGRST002',
      'PGRST003',
    }.contains(error.code);
  }
  return false;
}

String safeSyncErrorCode(Object error) {
  if (error is SyncPaginationException) {
    return 'Allineamento incompleto: ordine dei dati ricevuti non valido';
  }
  if (error is SyncIntentConflictException) {
    return 'Conflitto: scegli la versione nello storico attività';
  }
  if (error is PostgrestException) return 'Supabase ${error.code}';
  final type = safeSyncErrorType(error);
  if (isTransientSyncError(error)) return 'Rete $type';
  return type;
}

/// Known transport types remain stable in minified Web releases. Never include
/// exception messages, which can contain URLs, credentials or response content.
String safeSyncErrorType(Object error) {
  if (error is http.ClientException) return 'ClientException';
  if (error is TimeoutException) return 'TimeoutException';
  if (error is AuthRetryableFetchException) {
    return 'AuthRetryableFetchException';
  }
  if (error is SyncPaginationException) return 'SyncPaginationException';
  if (error is PostgrestException) return 'PostgrestException';
  return error.runtimeType.toString();
}
