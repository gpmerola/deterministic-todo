import 'package:deterministic_todo/features/h96_remote/h96_remote.dart';
import 'package:deterministic_todo/features/h96_remote/h96_remote_client.dart';
import 'package:deterministic_todo/features/h96_remote/h96_remote_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(H96RemoteClient.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late bool paired;

  setUp(() {
    calls = [];
    paired = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'status' => {
          'paired': paired,
          'name': 'H96 di prova',
          'host': '192.168.1.2',
          'state': 'IDLE',
        },
        'discover' => [
          {'name': 'RK3518', 'host': '192.168.1.2'},
        ],
        'send' || 'sendText' => true,
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> nativeEvent(String method, Map<String, Object?> args) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('feature is on by default and Android only', () {
    expect(h96RemoteEnabled, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(h96RemoteAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(h96RemoteAvailable, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  test('native state names map to client states', () {
    expect(H96RemoteClient.parseState('READY'), H96ConnectionState.ready);
    expect(H96RemoteClient.parseState('???'), H96ConnectionState.idle);
    expect(H96RemoteClient.parseFailure('NOT_PAIRED'), H96Failure.notPaired);
  });

  testWidgets('settings tile is hidden off Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: H96RemoteSettingsTile())),
    );
    expect(find.byType(ListTile), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('unpaired page offers discovery and lists the box', (
    tester,
  ) async {
    paired = false;
    await tester.pumpWidget(const MaterialApp(home: H96RemotePage()));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), isNot(contains('connect')));
    await tester.tap(find.byKey(const ValueKey('h96-discover')));
    await tester.pumpAndSettle();
    expect(find.text('RK3518'), findsOneWidget);
  });

  testWidgets('paired page connects, sends keys only when ready, and text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: H96RemotePage()));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), contains('connect'));

    // Not ready yet: the OK button is disabled, nothing is sent.
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'send'), isEmpty);

    await nativeEvent('state', {'state': 'READY', 'failure': 'NONE'});
    await nativeEvent('volume', {'level': 3, 'max': 15, 'muted': false});
    await tester.pump();
    expect(find.text('Connesso a H96 di prova'), findsOneWidget);
    expect(find.text('Volume 3 su 15'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump();
    final send = calls.lastWhere((c) => c.method == 'send');
    expect(send.arguments, {'command': 'OK'});

    await tester.enterText(find.byKey(const ValueKey('h96-text')), 'Città €');
    await tester.tap(find.byTooltip('Invia alla TV'));
    await tester.pump();
    final text = calls.lastWhere((c) => c.method == 'sendText');
    expect(text.arguments, {'text': 'Città €'});

    await nativeEvent('state', {'state': 'FAILED', 'failure': 'NOT_PAIRED'});
    await tester.pump();
    expect(find.text('Abbinamento non più valido'), findsOneWidget);
    expect(find.text('Abbina di nuovo'), findsOneWidget);
  });

  testWidgets('leaving the page disconnects', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: H96RemotePage()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('disconnect'));
  });
}
