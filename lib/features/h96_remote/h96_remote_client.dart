import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Connection states reported by the native session.
enum H96ConnectionState { idle, connecting, ready, reconnecting, failed }

/// Why a connection failed or is being retried.
enum H96Failure { none, unreachable, notPaired, closed }

class H96Box {
  const H96Box({required this.name, required this.host});

  final String name;
  final String host;
}

class H96Status {
  const H96Status({
    this.paired = false,
    this.name = '',
    this.host = '',
    this.state = H96ConnectionState.idle,
    this.failure = H96Failure.none,
    this.volumeLevel = -1,
    this.volumeMax = 0,
    this.muted = false,
    this.latencyMs = 0,
  });

  final bool paired;
  final String name;
  final String host;
  final H96ConnectionState state;
  final H96Failure failure;
  final int volumeLevel;
  final int volumeMax;
  final bool muted;

  /// Time the last connection took to open; 0 when unknown.
  final int latencyMs;

  bool get ready => state == H96ConnectionState.ready;

  H96Status copyWith({
    bool? paired,
    String? name,
    String? host,
    H96ConnectionState? state,
    H96Failure? failure,
    int? volumeLevel,
    int? volumeMax,
    bool? muted,
    int? latencyMs,
  }) => H96Status(
    paired: paired ?? this.paired,
    name: name ?? this.name,
    host: host ?? this.host,
    state: state ?? this.state,
    failure: failure ?? this.failure,
    volumeLevel: volumeLevel ?? this.volumeLevel,
    volumeMax: volumeMax ?? this.volumeMax,
    muted: muted ?? this.muted,
    latencyMs: latencyMs ?? this.latencyMs,
  );
}

/// Thin wrapper over the native channel. Typed text goes straight to the
/// platform and is never logged or kept here.
class H96RemoteClient {
  H96RemoteClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const channelName = 'app.deterministic.todo/h96_remote';

  final MethodChannel _channel;
  final ValueNotifier<H96Status> status = ValueNotifier(const H96Status());

  Future<void> refresh() async {
    final value = await _channel.invokeMapMethod<String, Object?>('status');
    if (value == null) return;
    status.value = status.value.copyWith(
      paired: value['paired'] == true,
      name: value['name'] as String? ?? '',
      host: value['host'] as String? ?? '',
      state: parseState(value['state'] as String?),
    );
  }

  Future<List<H96Box>> discover() async {
    final list = await _channel.invokeListMethod<Object?>('discover') ?? [];
    return [
      for (final item in list.whereType<Map<Object?, Object?>>())
        H96Box(
          name: item['name'] as String? ?? '',
          host: item['host'] as String? ?? '',
        ),
    ];
  }

  /// Throws [PlatformException] with code `invalid_host`, `tls_failed` or
  /// `unreachable`.
  Future<void> startPairing(String host, {String name = ''}) =>
      _channel.invokeMethod('startPairing', {'host': host, 'name': name});

  /// Throws [PlatformException] with code `bad_code`, `no_pairing` or
  /// `pairing_failed`.
  Future<void> finishPairing(String code) async {
    await _channel.invokeMethod('finishPairing', {'code': code});
    await refresh();
  }

  Future<void> cancelPairing() => _channel.invokeMethod('cancelPairing');

  Future<void> connect() => _channel.invokeMethod('connect');

  Future<void> disconnect() => _channel.invokeMethod('disconnect');

  /// Returns false when the command was dropped because the box is not ready.
  Future<bool> send(String command) async =>
      await _channel.invokeMethod<bool>('send', {'command': command}) ?? false;

  /// Starts or ends a held key; the box repeats it until the end.
  Future<bool> hold(String command, {required bool start}) async =>
      await _channel.invokeMethod<bool>('hold', {
        'command': command,
        'start': start,
      }) ??
      false;

  /// Opens YOUTUBE, NETFLIX, PRIME_VIDEO or GOOGLE_PLAY on the box.
  Future<bool> launch(String app) async =>
      await _channel.invokeMethod<bool>('launch', {'app': app}) ?? false;

  Future<bool> sendText(String text) async =>
      await _channel.invokeMethod<bool>('sendText', {'text': text}) ?? false;

  Future<void> forget() async {
    await _channel.invokeMethod('forget');
    status.value = const H96Status();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    status.dispose();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return;
    switch (call.method) {
      case 'state':
        status.value = status.value.copyWith(
          state: parseState(args['state'] as String?),
          failure: parseFailure(args['failure'] as String?),
        );
      case 'volume':
        status.value = status.value.copyWith(
          volumeLevel: args['level'] as int? ?? -1,
          volumeMax: args['max'] as int? ?? 0,
          muted: args['muted'] == true,
        );
      case 'latency':
        status.value = status.value.copyWith(
          latencyMs: args['millis'] as int? ?? 0,
        );
    }
  }

  @visibleForTesting
  static H96ConnectionState parseState(String? value) => switch (value) {
    'CONNECTING' => H96ConnectionState.connecting,
    'READY' => H96ConnectionState.ready,
    'RECONNECTING' => H96ConnectionState.reconnecting,
    'FAILED' => H96ConnectionState.failed,
    _ => H96ConnectionState.idle,
  };

  @visibleForTesting
  static H96Failure parseFailure(String? value) => switch (value) {
    'UNREACHABLE' => H96Failure.unreachable,
    'NOT_PAIRED' => H96Failure.notPaired,
    'CLOSED' => H96Failure.closed,
    _ => H96Failure.none,
  };
}

/// State of the WiZ bulb, as last reported over the LAN.
class H96Light {
  const H96Light({
    this.known = false,
    this.reachable = false,
    this.on = false,
    this.dimming = 100,
  });

  /// A bulb has been chosen on this phone.
  final bool known;
  final bool reachable;
  final bool on;
  final int dimming;

  H96Light copyWith({bool? on, int? dimming}) => H96Light(
    known: known,
    reachable: reachable,
    on: on ?? this.on,
    dimming: dimming ?? this.dimming,
  );
}

/// One bulb found on the LAN.
class H96Bulb {
  const H96Bulb({required this.host, required this.mac});

  final String host;
  final String mac;
}

/// WiZ light over the same channel; independent of the TV connection.
extension H96LightControl on H96RemoteClient {
  Future<H96Light> lightState() async {
    final value = await _channel.invokeMapMethod<String, Object?>('lightState');
    if (value == null) return const H96Light();
    final dimming = value['dimming'] as int? ?? -1;
    return H96Light(
      known: value['known'] == true,
      reachable: value['reachable'] == true,
      on: value['on'] == true,
      dimming: dimming < 10 ? 100 : dimming,
    );
  }

  Future<List<H96Bulb>> discoverLights() async {
    final list =
        await _channel.invokeListMethod<Object?>('lightDiscover') ?? [];
    return [
      for (final item in list.whereType<Map<Object?, Object?>>())
        H96Bulb(
          host: item['host'] as String? ?? '',
          mac: item['mac'] as String? ?? '',
        ),
    ];
  }

  Future<void> chooseLight(H96Bulb bulb) => _channel.invokeMethod(
    'lightChoose',
    {'host': bulb.host, 'mac': bulb.mac},
  );

  Future<void> forgetLight() => _channel.invokeMethod('lightForget');

  /// Returns true when the bulb acknowledged the command.
  Future<bool> lightCommand(
    String kind, [
    Map<String, Object> args = const {},
  ]) async {
    try {
      return await _channel.invokeMethod<bool>('lightCommand', {
            'kind': kind,
            ...args,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
