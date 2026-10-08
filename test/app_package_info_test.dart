import 'package:deterministic_todo/services/app_package_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test(
    'web identity comes from compiled code, native from installed package',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Mock',
        packageName: 'mock',
        version: '99.0.0',
        buildNumber: '9999',
        buildSignature: '',
      );
      final info = await appPackageInfo();
      expect(
        info.version,
        kIsWeb
            ? const String.fromEnvironment('TODO_VERSION', defaultValue: 'dev')
            : '99.0.0',
      );
      expect(
        info.buildNumber,
        kIsWeb
            ? const String.fromEnvironment(
                'TODO_BUILD',
                defaultValue: 'unknown',
              )
            : '9999',
      );
    },
  );
}
