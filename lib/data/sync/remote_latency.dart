import 'dart:async';

import '../../services/diagnostic_log_service.dart';

/// How a remote change reached this device.
enum RemoteChangePath { realtime, full }

/// End-to-end delay of remote task changes applied in one pass: arrival on
/// this device minus `updated_at`, the instant the editing device sent the
/// row. Both clocks are wall clocks of different devices, so values carry
/// their skew; negative or implausible values are counted as [ignored]
/// instead of being reported. No title, note or ID is kept.
class RemoteChangeLatency {
  const RemoteChangeLatency({
    required this.path,
    required this.count,
    required this.medianMs,
    required this.maxMs,
    required this.ignored,
    required this.measuredAt,
  });

  final RemoteChangePath path;
  final int count;
  final int medianMs;
  final int maxMs;
  final int ignored;
  final DateTime measuredAt;

  Map<String, Object> get diagnosticFields => {
    'path': path.name,
    'count': count,
    'median_ms': medianMs,
    'max_ms': maxMs,
    'ignored': ignored,
  };
}

/// Longer delays are not live propagation (a device that was paused or
/// offline catches up later) and would hide the figure of interest.
const maxPlausibleRemoteLatency = Duration(minutes: 10);

/// Reads `updated_at` (microseconds since the epoch on the editing device)
/// without trusting its type; returns null when absent or malformed.
int? remoteUpdatedAtMicros(Map<String, dynamic> row) =>
    switch (row['updated_at']) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };

/// Collects samples over the pages of one pass. Rows written by
/// [localDeviceId] (echoes of this device's own uploads) are skipped.
class RemoteLatencySamples {
  RemoteLatencySamples(this.localDeviceId);

  final String? localDeviceId;
  final _samples = <int>[];
  int _ignored = 0;

  /// [arrivedAt] is when the response holding [rows] reached this device.
  void add(Iterable<Map<String, dynamic>> rows, DateTime arrivedAt) {
    final arrival = arrivedAt.toUtc().microsecondsSinceEpoch;
    for (final row in rows) {
      final device = row['device_id'];
      if (device is! String || device == localDeviceId) continue;
      final updatedAt = remoteUpdatedAtMicros(row);
      final delay = updatedAt == null ? null : arrival - updatedAt;
      if (delay == null ||
          delay < 0 ||
          delay > maxPlausibleRemoteLatency.inMicroseconds) {
        _ignored++;
        continue;
      }
      _samples.add(delay ~/ Duration.microsecondsPerMillisecond);
    }
  }

  /// Null when no row from another device was seen, so local echoes and
  /// equal versions report nothing.
  RemoteChangeLatency? summary(RemoteChangePath path, DateTime measuredAt) {
    if (_samples.isEmpty && _ignored == 0) return null;
    final sorted = List.of(_samples)..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.isEmpty
        ? 0
        : sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) ~/ 2;
    return RemoteChangeLatency(
      path: path,
      count: sorted.length,
      medianMs: median,
      maxMs: sorted.isEmpty ? 0 : sorted.last,
      ignored: _ignored,
      measuredAt: measuredAt.toUtc(),
    );
  }
}

void logRemoteLatency(RemoteChangeLatency latency) => unawaited(
  DiagnosticLogService.instance.event(
    'remote_change_latency',
    fields: latency.diagnosticFields,
  ),
);
