import 'package:flutter/services.dart';

final class DailyMovementProgress {
  const DailyMovementProgress({
    required this.day,
    required this.steps,
    required this.distanceMeters,
    required this.calories,
    required this.updatedAt,
  });

  final String day;
  final int steps;
  final double distanceMeters;
  final double calories;
  final DateTime updatedAt;
}

final class RunTrackerService {
  const RunTrackerService._();

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
}
