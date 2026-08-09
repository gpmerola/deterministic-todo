import 'package:flutter/services.dart';

final class RunTrackerService {
  const RunTrackerService._();

  static const _channel = MethodChannel('app.deterministic.todo/run_tracker');

  static Future<void> open() => _channel.invokeMethod<void>('open');
}
