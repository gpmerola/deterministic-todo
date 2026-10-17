import 'dart:async';

import 'package:deterministic_todo/services/calendar_shortcut_service.dart';
import 'package:deterministic_todo/ui/app_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  test(
    'cold and warm launches are consumed once; pin status stays explicit',
    () async {
      var pending = true;
      var opens = 0;
      var pinStatus = 'requested';
      messenger.setMockMethodCallHandler(CalendarShortcutService.channel, (
        call,
      ) async {
        if (call.method == 'pin') return pinStatus;
        final value = pending;
        pending = false;
        return value;
      });
      final service = CalendarShortcutService();
      addTearDown(() {
        service.detach();
        messenger.setMockMethodCallHandler(
          CalendarShortcutService.channel,
          null,
        );
      });
      await service.attach(() async {
        opens++;
      });
      expect(opens, 1);
      Future<void> signal() async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          CalendarShortcutService.channel.name,
          codec.encodeMethodCall(const MethodCall('calendarRequested')),
          (_) => done.complete(),
        );
        await done.future;
      }

      await signal();
      expect(opens, 1);
      pending = true;
      await signal();
      expect(opens, 2);
      expect(await service.pin(), 'requested');
      pinStatus = 'alreadyPinned';
      expect(await service.pin(), 'alreadyPinned');
      pinStatus = 'unsupported';
      expect(await service.pin(), 'unsupported');
      expect(AppSection.agenda.label, 'Calendario');
    },
  );
}
