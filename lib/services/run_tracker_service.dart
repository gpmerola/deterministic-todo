import 'package:flutter/services.dart';

/// Phone steps of the current civil day, read from local Android storage.
final class DailyMovementProgress {
  const DailyMovementProgress({
    required this.day,
    required this.steps,
    this.collectionStatus = 'not_started',
    this.coverage = 'not_established',
    this.lastImport,
  });

  final String day;
  final int steps;
  final String collectionStatus;
  final String coverage;
  final DateTime? lastImport;

  @override
  bool operator ==(Object other) =>
      other is DailyMovementProgress &&
      other.day == day &&
      other.steps == steps &&
      other.collectionStatus == collectionStatus &&
      other.coverage == coverage &&
      other.lastImport == lastImport;

  @override
  int get hashCode =>
      Object.hash(day, steps, collectionStatus, coverage, lastImport);
}

/// Daily step count only: GPS sessions, Amazfit and diagnostics are archived
/// (see docs/archive/MOVIMENTO.md).
final class RunTrackerService {
  const RunTrackerService._();

  /// Android imports complete minutes at most once a minute; refreshing more
  /// often while visible would only reread unchanged rows.
  static const foregroundRefreshInterval = Duration(minutes: 1);

  static const _channel = MethodChannel('app.deterministic.todo/run_tracker');

  static Future<DailyMovementProgress?> dailyMovement() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'dailyMovement',
      );
      if (value == null) return null;
      final lastImportMillis =
          (value['phone_last_import_ms'] as num?)?.toInt() ?? 0;
      return DailyMovementProgress(
        day: value['day'] as String? ?? '',
        steps: (value['steps'] as num?)?.toInt() ?? 0,
        collectionStatus:
            value['phone_accounting_reason'] as String? ?? 'not_started',
        coverage: value['phone_coverage'] as String? ?? 'not_established',
        lastImport: lastImportMillis > 0
            ? DateTime.fromMillisecondsSinceEpoch(lastImportMillis)
            : null,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<int> getStepGoal() async {
    try {
      return await _channel.invokeMethod<int>('getStepGoal') ?? 10000;
    } on MissingPluginException {
      return 10000;
    } on PlatformException {
      return 10000;
    }
  }

  static Future<void> requestStepPermission() =>
      _channel.invokeMethod<void>('requestStepPermission');

  static Future<int> setStepGoal(int goal) async {
    final normalized = goal.clamp(1000, 100000).toInt();
    try {
      return await _channel.invokeMethod<int>('setStepGoal', {
            'goal': normalized,
          }) ??
          normalized;
    } on MissingPluginException {
      return normalized;
    }
  }
}
