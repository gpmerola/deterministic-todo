import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/semble_availability.dart';
import '../../domain/task.dart';
import '../../services/semble_service.dart';

/// Semble colours, one green family (build 300, user request): visits
/// solid green, bookable time a light green tint, blocked time grey-green
/// stripes. Events of other calendars inside bookable time get an amber
/// edge.
abstract final class SemblePalette {
  static bool _dark(ColorScheme scheme) => scheme.brightness == Brightness.dark;

  static Color visit(ColorScheme scheme) =>
      _dark(scheme) ? const Color(0xFF4CAF7A) : const Color(0xFF1B7F4B);

  static Color availableEdge(ColorScheme scheme) =>
      _dark(scheme) ? const Color(0xFF7FD6A4) : const Color(0xFF2FA866);

  static Color available(ColorScheme scheme) =>
      availableEdge(scheme).withValues(alpha: _dark(scheme) ? 0.16 : 0.12);

  static Color _blocked(ColorScheme scheme) =>
      _dark(scheme) ? const Color(0xFF9DB5A6) : const Color(0xFF52705E);

  static Color unavailable(ColorScheme scheme) =>
      _blocked(scheme).withValues(alpha: 0.3);

  /// Solid swatches of the legend in Settings.
  static Color legendAvailable(ColorScheme scheme) =>
      availableEdge(scheme).withValues(alpha: 0.9);

  static Color legendUnavailable(ColorScheme scheme) =>
      _blocked(scheme).withValues(alpha: 0.6);

  static Color overlap(ColorScheme scheme) =>
      _dark(scheme) ? const Color(0xFFFFC857) : const Color(0xFFD08A00);
}

/// Semble availability behind the events of one day column (build 285):
/// a green tint where the clinician is bookable, grey stripes where Semble
/// blocks the time. Never tappable, so free-time taps still create events.
class AgendaSembleBands extends StatelessWidget {
  const AgendaSembleBands({
    required this.day,
    required this.scale,
    this.left = 0,
    this.layer,
    this.entries = const [],
    super.key,
  });

  /// The day's events; their time is not drawn as free.
  final List<AgendaEntry> entries;

  final CivilDate day;
  final TimelineScale scale;

  /// Gutter kept clear (the hour labels of the day view).
  final double left;

  /// Defaults to [SembleLayer.shared].
  final SembleLayer? layer;

  /// Fill colours, shared with the legend in Settings.
  static Color availableColor(ColorScheme scheme) =>
      SemblePalette.available(scheme);

  static Color unavailableColor(ColorScheme scheme) =>
      SemblePalette.unavailable(scheme);

  @override
  Widget build(BuildContext context) {
    final source = layer ?? SembleLayer.shared;
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      left: left,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: source,
          builder: (context, _) {
            final bands = source.bandsFor(day, busy: entries);
            if (bands.isEmpty) return const SizedBox.shrink();
            return CustomPaint(
              key: ValueKey('agenda-semble-$day'),
              painter: _BandsPainter(
                bands: bands,
                scale: scale,
                available: availableColor(scheme),
                accent: SemblePalette.availableEdge(
                  scheme,
                ).withValues(alpha: 0.7),
                unavailable: unavailableColor(scheme),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BandsPainter extends CustomPainter {
  _BandsPainter({
    required this.bands,
    required this.scale,
    required this.available,
    required this.accent,
    required this.unavailable,
  });

  final List<SembleBand> bands;
  final TimelineScale scale;
  final Color available;
  final Color accent;
  final Color unavailable;

  @override
  void paint(Canvas canvas, Size size) {
    for (final band in bands) {
      final rect = Rect.fromLTRB(
        0,
        scale.y(band.startMinute),
        size.width,
        scale.y(band.endMinute),
      );
      if (rect.height <= 0) continue;
      switch (band.kind) {
        case SembleBandKind.available:
          canvas.drawRect(rect, Paint()..color = available);
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top, 3, rect.height),
            Paint()..color = accent,
          );
        case SembleBandKind.unavailable:
          canvas.save();
          canvas.clipRect(rect);
          final stripe = Paint()
            ..color = unavailable
            ..strokeWidth = 1.5;
          for (var x = -rect.height; x < rect.width; x += 8) {
            canvas.drawLine(
              Offset(rect.left + x, rect.bottom),
              Offset(rect.left + x + rect.height, rect.top),
              stripe,
            );
          }
          canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BandsPainter old) =>
      old.scale != scale ||
      old.available != available ||
      old.unavailable != unavailable ||
      !_same(old.bands, bands);

  static bool _same(List<SembleBand> a, List<SembleBand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
