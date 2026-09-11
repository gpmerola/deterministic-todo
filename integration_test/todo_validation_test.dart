import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test/export_service_test.dart' as backup_tests;
import '../test/outbox_efficiency_test.dart' as outbox_tests;
import '../test/sync_hardening_test.dart' as sync_tests;
import '../test/sync_lifecycle_test.dart' as lifecycle_tests;
import '../test/sync_pull_performance_test.dart' as pull_tests;
import '../test/todo_ux_hardening_test.dart' as ux_tests;

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TODO_VALIDATION')) {
    throw StateError('Use the isolated validation build.');
  }
  final package = await PackageInfo.fromPlatform();
  if (!package.packageName.endsWith('.dev.validation')) {
    throw StateError('Refusing to run fixtures in an operational package.');
  }
  ux_tests.main(includeDesktop: false);
  sync_tests.main();
  backup_tests.main();
  lifecycle_tests.main();
  pull_tests.main();
  outbox_tests.main();
}
