import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/services/diagnostic_log_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'export preserves conflicts and pagination evidence but excludes content',
    () async {
      final directory = await Directory.systemTemp.createTemp('sync-log-test-');
      addTearDown(() => directory.delete(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory.path,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(pathChannel, null));
      final log = DiagnosticLogService.instance;
      await log.initialize();
      await log.event(
        'sync_completed',
        fields: {
          'conflicts': 2,
          'pending': 3,
          'pull_all': true,
          'pull_pages': 4,
          'pulled_rows': 426,
          'pull_table': 'tasks',
          'title': 'Synthetic private title',
          'token': 'synthetic-secret',
        },
      );
      final exported = await log.exportData();
      final rows = utf8
          .decode(exported!.bytes)
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map);
      final event = rows.last;
      expect(event['conflicts'], 2);
      expect(event['pending'], 3);
      expect(event['pull_pages'], 4);
      expect(event['pulled_rows'], 426);
      expect(event['pull_table'], 'tasks');
      expect(event['pull_all'], true);
      expect(event.containsKey('title'), isFalse);
      expect(event.containsKey('token'), isFalse);
    },
  );
}
