import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Web identity belongs to the running bundle, never a separately fetched
/// version.json (which can already describe a newer deployment).
Future<PackageInfo> appPackageInfo() async {
  if (!kIsWeb) return PackageInfo.fromPlatform();
  return PackageInfo(
    appName: 'Deterministic Todo',
    packageName: 'deterministic_todo',
    version: const String.fromEnvironment('TODO_VERSION', defaultValue: 'dev'),
    buildNumber: const String.fromEnvironment(
      'TODO_BUILD',
      defaultValue: 'unknown',
    ),
  );
}
