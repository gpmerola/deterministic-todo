import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/services/auto_backup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Real Android Keystore + MediaStore round trip, synthetic bytes only, in the
/// isolated `.dev.validation` package. Removes its own files at the end.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TODO_VALIDATION')) {
    throw StateError('Use the isolated validation build.');
  }
  const channel = MethodChannel('app.deterministic.todo/backup');
  const store = MethodChannelBackupStore();
  final plain = Uint8List.fromList(
    utf8.encode('{"format":"deterministic_todo","synthetic":"àè 🧪"}'),
  );

  testWidgets('encrypted backup round trip on device', (tester) async {
    final package = await PackageInfo.fromPlatform();
    if (!package.packageName.endsWith('.dev.validation')) {
      throw StateError('Refusing to run fixtures in an operational package.');
    }
    // ignore: avoid_print
    print('auto_backup_smoke: start');
    await channel.invokeMethod<bool>('deleteAllForValidation');
    expect(await store.configured(), isFalse);
    await expectLater(
      store.write('todo-20261012T090000Z.tdb', plain, keep: 2),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'not_configured',
        ),
      ),
    );
    final code = await store.setup();
    expect(
      code,
      matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){12}[0-9A-HJKMNP-TV-Z]{4}$')),
    );
    expect(await store.setup(), code, reason: 'setup is idempotent');
    expect(await store.configured(), isTrue);

    for (final day in ['10', '11', '12']) {
      await store.write('todo-202610${day}T090000Z.tdb', plain, keep: 2);
    }
    final names = (await store.list()).map((e) => e.name).toList();
    expect(names, ['todo-20261011T090000Z.tdb', 'todo-20261012T090000Z.tdb']);
    expect(await store.read(names.last), plain);

    final file = File(
      '/storage/emulated/0/Documents/Todo backup/${names.last}',
    );
    final sealed = await file.readAsBytes();
    expect(
      utf8.decode(sealed, allowMalformed: true).contains('synthetic'),
      isFalse,
    );
    expect(await store.decrypt(sealed), plain);
    expect(await store.decrypt(sealed, code: code.toLowerCase()), plain);
    await expectLater(
      store.decrypt(
        sealed,
        code:
            '0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000-0000',
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'key_mismatch'),
      ),
    );
    await expectLater(
      store.decrypt(sealed, code: 'not a code'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'invalid_code'),
      ),
    );

    await channel.invokeMethod<bool>('deleteAllForValidation');
    expect(await store.list(), isEmpty);
    expect(await store.configured(), isFalse);
    // ignore: avoid_print
    print('auto_backup_smoke: all checks passed');
  });
}
