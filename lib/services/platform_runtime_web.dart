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

/// Asks the browser to confirm closing or reloading the page while edits
/// are still waiting to be sent. The browser shows its own generic text.
void guardPageUnload(bool Function() hasUnsentWork) {
  _window.addEventListener(
    'beforeunload',
    ((_BeforeUnloadEvent event) {
      if (!hasUnsentWork()) return;
      event.preventDefault();
      event.returnValue = '';
    }).toJS,
  );
}

void reloadPage() => _window.location.reload();

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external _Location get location;
}

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}

extension type _BeforeUnloadEvent._(JSObject _) implements JSObject {
  external void preventDefault();
  external set returnValue(String value);
}
