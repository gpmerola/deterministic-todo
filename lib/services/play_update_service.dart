import 'package:flutter/services.dart';

import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

enum PlayUpdateStatus { started, available, unavailable, unsupported, error }

typedef PlayUpdateInvoker = Future<Object?> Function(bool startIfAvailable);

/// Bridge to Google Play's official in-app update API.
///
/// The native implementation exists only in the Play flavor. Direct APKs and
/// web builds therefore keep their existing updater and carry no Play Core
/// dependency.
class PlayUpdateService {
  PlayUpdateService({this.invoker});

  static const _channel = MethodChannel('app.deterministic.todo/play_update');
  final PlayUpdateInvoker? invoker;

  Future<PlayUpdateStatus> check({required bool startIfAvailable}) async {
    if (invoker == null && !isAndroidPlatform) {
      return PlayUpdateStatus.unsupported;
    }
    try {
      final response =
          await (invoker?.call(startIfAvailable) ??
              _channel.invokeMethod<Object?>('checkUpdate', {
                'startIfAvailable': startIfAvailable,
              }));
      final value = response is Map ? response['status'] : response;
      return PlayUpdateStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => PlayUpdateStatus.error,
      );
    } on MissingPluginException {
      return PlayUpdateStatus.unsupported;
    } on Object {
      return PlayUpdateStatus.error;
    }
  }
}
