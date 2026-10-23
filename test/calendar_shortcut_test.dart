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
      Object pending = true;
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
      final targets = <CalendarLaunch?>[];
      await service.attach((target) async {
        opens++;
        targets.add(target);
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
      // A conflict notification names the event start only (build 306).
      pending = {'start': 1793530800000, 'single': true};
      await signal();
      expect(opens, 3);
      expect(targets.first, isNull);
      expect(targets.last!.start.millisecondsSinceEpoch, 1793530800000);
      expect(targets.last!.single, isTrue);
      expect(CalendarLaunch.parse(true), isNull);
      expect(CalendarLaunch.parse({'start': 0}), isNull);
      expect(await service.pin(), 'requested');
      pinStatus = 'alreadyPinned';
      expect(await service.pin(), 'alreadyPinned');
      pinStatus = 'unsupported';
      expect(await service.pin(), 'unsupported');
      expect(AppSection.agenda.label, 'Calendario');
    },
  );
}
