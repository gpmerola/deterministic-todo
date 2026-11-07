import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'memory_snapshot.dart';

const bool isWebPlatform = false;

/// Semble on the phone (key in the Android Keystore) and, from build 326, in
/// the browser (key kept only in that browser).
bool get sembleSupported => isAndroidPlatform;
bool get isAndroidPlatform => Platform.isAndroid;
String get operatingSystemName => Platform.operatingSystem;
int get currentRssBytes => ProcessInfo.currentRss;

const _runtimeMetrics = MethodChannel('app.deterministic.todo/runtime_metrics');

Future<MemorySnapshot?> readMemorySnapshot() async {
  if (!Platform.isAndroid) return null;
  try {
    final values = await _runtimeMetrics.invokeMapMethod<String, int>(
      'memorySnapshot',
    );
    if (values == null) return null;
    return MemorySnapshot.fromKilobytes(values);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<int> databaseSizeBytes() async {
  final support = await getApplicationSupportDirectory();
  final database = File(p.join(support.path, 'deterministic_todo.sqlite'));
  return await database.exists() ? database.length() : 0;
}

/// Only the web needs it; native code reads the zone from Android.
String? get browserTimeZoneId => null;

/// Web only: the browser asks before closing a page with unsent edits.
void guardPageUnload(bool Function() hasUnsentWork) {}

/// Web only: reloads the page to run a newer deployment.
void reloadPage() {}
