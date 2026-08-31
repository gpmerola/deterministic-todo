import 'package:flutter/services.dart';

final class DailyMovementProgress {
  const DailyMovementProgress({
    required this.day,
    required this.steps,
    required this.distanceMeters,
    required this.calories,
    required this.updatedAt,
    required this.phoneSteps,
    required this.bipSteps,
    required this.source,
  });

  final String day;
  final int steps;
  final double distanceMeters;
  final double calories;
  final DateTime updatedAt;
  final int phoneSteps;
  final int bipSteps;
  final String source;
}

final class MovementSessionState {
  const MovementSessionState({
    required this.recording,
    required this.sessionId,
    required this.activityType,
    required this.startedAt,
    required this.distanceMeters,
    required this.steps,
    required this.accuracyMeters,
    required this.gpsStatus,
    required this.passiveActive,
    required this.driveConfigured,
    required this.automaticStatus,
    required this.driveStatus,
  });

  final bool recording;
  final int sessionId;
  final String activityType;
  final DateTime? startedAt;
  final double distanceMeters;
  final int steps;
  final double accuracyMeters;
  final String gpsStatus;
  final bool passiveActive;
  final bool driveConfigured;
  final String automaticStatus;
  final String driveStatus;
}

final class RunTrackerService {
  const RunTrackerService._();

  /// One hardware-counter reading while the UI is visible; no background polling.
  static const foregroundRefreshInterval = Duration(seconds: 30);

  static const _channel = MethodChannel('app.deterministic.todo/run_tracker');

  static Future<void> open() => _channel.invokeMethod<void>('open');

  static Future<DailyMovementProgress?> dailyMovement() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'dailyMovement',
      );
      if (value == null) return null;
      return DailyMovementProgress(
        day: value['day'] as String? ?? '',
        steps: (value['steps'] as num?)?.toInt() ?? 0,
        distanceMeters: (value['distance_m'] as num?)?.toDouble() ?? 0,
        calories: (value['calories'] as num?)?.toDouble() ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (value['updated_at_ms'] as num?)?.toInt() ?? 0,
        ),
        phoneSteps: (value['phone_steps'] as num?)?.toInt() ?? 0,
        bipSteps: (value['bip_steps'] as num?)?.toInt() ?? 0,
        source: value['source'] as String? ?? 'phone_step_counter',
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

  static Future<MovementSessionState?> movementState() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'movementState',
      );
      if (value == null) return null;
      final startedAtMillis = (value['started_at_ms'] as num?)?.toInt() ?? 0;
      return MovementSessionState(
        recording: value['recording'] as bool? ?? false,
        sessionId: (value['session_id'] as num?)?.toInt() ?? 0,
        activityType: value['activity_type'] as String? ?? '',
        startedAt: startedAtMillis > 0
            ? DateTime.fromMillisecondsSinceEpoch(startedAtMillis)
            : null,
        distanceMeters: (value['distance_m'] as num?)?.toDouble() ?? 0,
        steps: (value['session_steps'] as num?)?.toInt() ?? 0,
        accuracyMeters: (value['accuracy_m'] as num?)?.toDouble() ?? 0,
        gpsStatus: value['gps_status'] as String? ?? 'GPS spento',
        passiveActive: value['passive_active'] as bool? ?? false,
        driveConfigured: value['drive_configured'] as bool? ?? false,
        automaticStatus: value['automatic_status'] as String? ?? '',
        driveStatus: value['drive_status'] as String? ?? '',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<String> startMovement(String activityType) async {
    return await _channel.invokeMethod<String>('startMovement', {
          'activity_type': activityType,
        }) ??
        'error';
  }

  static Future<void> stopMovement() =>
      _channel.invokeMethod<void>('stopMovement');

  static Future<String> uploadMovementData() async =>
      await _channel.invokeMethod<String>('uploadMovementData') ?? 'error';

  static Future<String> setPassiveMonitoring(bool enabled) async =>
      await _channel.invokeMethod<String>('setPassiveMonitoring', {
        'enabled': enabled,
      }) ??
      'error';
}
