import 'package:flutter/widgets.dart';
import '../../data/sync/sync_service.dart';

/// Pauses and resumes sync from the binding, next to [SyncService.start].
/// Widget observers are not enough: in background Flutter builds no frames,
/// so an app started there would never reach the widget that observes it.
AppLifecycleListener bindSyncToLifecycle(SyncService service) {
  if (isBackgroundLifecycle(WidgetsBinding.instance.lifecycleState)) {
    service.pause();
  }
  return AppLifecycleListener(
    onStateChange: (state) {
      if (isBackgroundLifecycle(state)) {
        service.pause();
      } else if (state == AppLifecycleState.resumed) {
        service.resume();
      }
    },
  );
}

/// Not visible to the user. `inactive` alone is a transient interruption.
bool isBackgroundLifecycle(AppLifecycleState? state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached ||
    state == AppLifecycleState.hidden;
