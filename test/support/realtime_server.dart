import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Loopback Realtime (Phoenix protocol 2.0.0) fixture: answers joins and
/// heartbeats. With [answerLeave] false it never acknowledges `phx_leave`,
/// like a socket whose peer vanished while Android froze the process.
class SyntheticRealtimeServer {
  late final HttpServer _server;
  final _sockets = <WebSocket>{};
  bool answerLeave = true;
  int joins = 0;
  int leaves = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen(
        (raw) => _handle(socket, raw as String),
        onDone: () => _sockets.remove(socket),
        cancelOnError: true,
      );
    });
  }

  void _handle(WebSocket socket, String raw) {
    final frame = jsonDecode(raw) as List<dynamic>;
    final [joinRef, ref, topic, event, payload] = frame;
    void reply(Map<String, dynamic> response) {
      if (!_sockets.contains(socket)) return;
      socket.add(
        jsonEncode([
          joinRef,
          ref,
          topic,
          'phx_reply',
          {'status': 'ok', 'response': response},
        ]),
      );
    }

    switch (event) {
      case 'phx_join':
        joins++;
        final config = (payload as Map)['config'] as Map;
        var id = 0;
        reply({
          'postgres_changes': [
            for (final binding in config['postgres_changes'] as List)
              {...binding as Map, 'id': ++id},
          ],
        });
      case 'phx_leave':
        leaves++;
        if (answerLeave) reply({});
      case 'heartbeat':
      case 'access_token':
        reply({});
    }
  }

  Future<void> close() async {
    final open = _sockets.toList();
    _sockets.clear();
    for (final socket in open) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}
