import 'dart:js_interop';

import 'memory_snapshot.dart';

const bool isWebPlatform = true;
bool get isAndroidPlatform => false;
String get operatingSystemName => 'web';
int get currentRssBytes => 0;
Future<MemorySnapshot?> readMemorySnapshot() async => null;
Future<int> databaseSizeBytes() async => 0;

/// IANA zone of the browser ("Europe/London"), never an abbreviation.
String? get browserTimeZoneId {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone;
  } catch (_) {
    return null;
  }
}

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external String get timeZone;
}
