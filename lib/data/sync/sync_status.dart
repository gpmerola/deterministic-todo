enum SyncPhase { disabled, offline, syncing, current, error }

enum SyncStage {
  idle,
  overview,
  projects,
  taskUpload,
  receipt,
  taskPull,
  taskMerge,
  purgePull,
}

final class SyncWriteVerificationException implements Exception {
  const SyncWriteVerificationException();
}

class SyncSnapshot {
  const SyncSnapshot(
    this.phase, {
    this.pending = 0,
    this.lastSuccess,
    this.error,
    this.stage = SyncStage.idle,
    this.lastFailure,
    this.lastError,
    this.lastFailureStage,
    this.lastRecovery,
    this.retryAt,
    this.consecutiveFailures = 0,
    this.alignment,
  });
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSuccess;
  final String? error;
  final SyncStage stage;
  final DateTime? lastFailure;
  final String? lastError;
  final SyncStage? lastFailureStage;
  final DateTime? lastRecovery;
  final DateTime? retryAt;
  final int consecutiveFailures;

  /// Result of the last complete check against the server; null until one ran.
  final SyncAlignment? alignment;
}

/// Server alignment measured by bucket fingerprints after a complete pull.
/// [divergedBuckets] counts groups of tasks still different from the server
/// without pending local changes. Not polled: refreshed only by sync cycles.
class SyncAlignment {
  const SyncAlignment(
    this.divergedBuckets, {
    required this.checkedAt,
    required this.contentChecked,
    this.repaired = false,
  });
  final int divergedBuckets;
  final DateTime checkedAt;

  /// False when the server only offers v1 fingerprints (versions, no content).
  final bool contentChecked;

  /// True after a user-requested complete pull.
  final bool repaired;
  bool get aligned => divergedBuckets == 0;
}
