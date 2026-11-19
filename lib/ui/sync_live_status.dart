import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/sync/sync_service.dart';

/// Pull-to-refresh on task lists: one full check with a fresh remote read.
/// Without an account it does nothing. The gesture's spinner waits at most
/// [limit]; the check itself carries on in background and SQLite stays the
/// source of what the list shows, so nothing waits for the network.
Future<void> pullToSync(
  SyncService? service, {
  Duration limit = const Duration(seconds: 8),
}) async {
  if (service == null || service.client.auth.currentUser == null) return;
  try {
    await service.sync(freshSnapshot: true).timeout(limit);
  } on Object {
    // A timeout or failure is shown by the sync status, not by the gesture.
  }
}

/// «aggiornato X fa» with coarse steps, so a modest refresh stays truthful.
String syncAgeLabel(DateTime? at, DateTime now) {
  if (at == null) return 'mai aggiornato';
  final age = now.difference(at);
  if (age.inSeconds < 10) return 'aggiornato adesso';
  if (age.inSeconds < 60) return 'aggiornato ${age.inSeconds} s fa';
  if (age.inMinutes < 60) return 'aggiornato ${age.inMinutes} min fa';
  final local = at.toLocal();
  final today = now.toLocal();
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return 'aggiornato alle '
      '${DateFormat(sameDay ? 'HH:mm' : 'd MMM HH:mm', 'it').format(local)}';
}

String realtimeLinkLabel(RealtimeLink link) => switch (link) {
  RealtimeLink.connected => 'Live',
  RealtimeLink.connecting => 'Live in collegamento…',
  RealtimeLink.disconnected => 'Live non collegato',
};

String remoteLatencyLabel(RemoteChangeLatency latency) {
  final via = latency.path == RemoteChangePath.realtime
      ? 'Realtime'
      : 'controllo completo';
  final time = DateFormat(
    'HH:mm:ss',
    'it',
  ).format(latency.measuredAt.toLocal());
  final many = latency.count > 1
      ? ' · max ${latency.maxMs} ms su ${latency.count}'
      : '';
  return '${latency.medianMs} ms$many · via $via · $time';
}

/// Next refresh of the relative age: every 10 s in the first minute, then
/// every 30 s. Only while the widget is mounted (the view is open).
Duration syncAgeRefresh(DateTime? at, DateTime now) =>
    at != null && now.difference(at) < const Duration(minutes: 1)
    ? const Duration(seconds: 10)
    : const Duration(seconds: 30);

/// «Live · aggiornato 12 s fa». Rebuilds on channel and sync events; the
/// relative age is refreshed by a single one-shot timer while mounted.
class SyncLiveLine extends StatefulWidget {
  const SyncLiveLine({required this.service, this.style, super.key});

  final SyncService service;
  final TextStyle? style;

  @override
  State<SyncLiveLine> createState() => _SyncLiveLineState();
}

class _SyncLiveLineState extends State<SyncLiveLine> {
  StreamSubscription<SyncSnapshot>? _snapshots;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _snapshots = widget.service.snapshots.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _snapshots?.cancel();
    super.dispose();
  }

  void _schedule(DateTime? at) {
    _tick?.cancel();
    _tick = Timer(syncAgeRefresh(at, DateTime.now()), () {
      // A covered route keeps its widgets mounted: skip the rebuild there.
      if (!mounted) return;
      if (TickerMode.getValuesNotifier(context).value.enabled) {
        setState(() {});
      }
      _schedule(widget.service.latest.lastSuccess);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RealtimeLink>(
    valueListenable: widget.service.realtimeLink,
    builder: (context, link, _) {
      final at = widget.service.latest.lastSuccess;
      _schedule(at);
      return Text(
        '${realtimeLinkLabel(link)} · ${syncAgeLabel(at, DateTime.now())}',
        key: const ValueKey('sync-live-line'),
        style: widget.style,
      );
    },
  );
}
