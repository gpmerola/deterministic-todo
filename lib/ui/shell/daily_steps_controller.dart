import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/database.dart';
import '../../services/run_tracker_service.dart';

/// Today's phone steps and goal for the shell's step ring.
///
/// Owned by the shell but kept out of its state: a refresh notifies only the
/// widgets listening here, and only when something visible changed, so the
/// minute tick never rebuilds the whole shell.
class DailyStepsController extends ChangeNotifier {
  DailyStepsController({
    required AppDatabase database,
    this.onGoalReached,
    Future<DailyMovementProgress?> Function()? readProgress,
    Future<int> Function()? readGoal,
    Future<int> Function(int goal)? writeGoal,
  }) : _database = database, // ignore: prefer_initializing_formals
       _readProgress = readProgress ?? RunTrackerService.dailyMovement,
       _readGoal = readGoal ?? RunTrackerService.getStepGoal,
       _writeGoal = writeGoal ?? RunTrackerService.setStepGoal;

  static const celebratedDayKey = 'step_goal_celebrated_day';

  final AppDatabase _database;
  final Future<DailyMovementProgress?> Function() _readProgress;
  final Future<int> Function() _readGoal;
  final Future<int> Function(int goal) _writeGoal;

  /// Called once per civil day when the goal is first reached.
  final VoidCallback? onGoalReached;

  DailyMovementProgress? _progress;
  int _goal = 10000;
  String? _celebratedDay;
  bool _settingsLoaded = false;
  bool _disposed = false;
  Timer? _timer;

  DailyMovementProgress? get progress => _progress;
  int get goal => _goal;

  /// [full] false reads only the steps: goal and saved celebration change
  /// only through this app, and are reread on resume.
  Future<void> refresh({bool full = true}) async {
    final loadSettings = full || !_settingsLoaded;
    final results = await Future.wait<Object?>([
      _readProgress(),
      if (loadSettings) _readGoal(),
      if (loadSettings)
        (_database.select(
          _database.appSettings,
        )..where((row) => row.key.equals(celebratedDayKey))).getSingleOrNull(),
    ]);
    if (_disposed) return;
    final progress = results[0] as DailyMovementProgress?;
    final goal = loadSettings ? results[1] as int : _goal;
    if (loadSettings) {
      _settingsLoaded = true;
      _celebratedDay ??= (results[2] as AppSetting?)?.value;
    }
    final celebrate =
        progress != null &&
        progress.steps >= goal &&
        _celebratedDay != progress.day;
    if (progress == _progress && goal == _goal && !celebrate) return;
    _progress = progress;
    _goal = goal;
    if (celebrate) _celebratedDay = progress.day;
    notifyListeners();
    if (celebrate) {
      await _database
          .into(_database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: celebratedDayKey,
              value: progress.day,
            ),
          );
      if (!_disposed) onGoalReached?.call();
    }
  }

  Future<void> setGoal(int value) async {
    final goal = await _writeGoal(value);
    if (_disposed) return;
    _goal = goal;
    // Lowering then raising the goal on the same day may celebrate again.
    if ((_progress?.steps ?? 0) < goal) _celebratedDay = null;
    notifyListeners();
  }

  /// Rereads the steps every [RunTrackerService.foregroundRefreshInterval]
  /// while [active] holds (the app is in the foreground).
  void startPeriodicRefresh(bool Function() active) {
    _timer?.cancel();
    _timer = Timer.periodic(RunTrackerService.foregroundRefreshInterval, (_) {
      if (active()) unawaited(refresh(full: false));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
