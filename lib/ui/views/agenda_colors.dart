import 'package:flutter/material.dart';

/// Calendar-only colours; preserve typography, accessibility and app settings.
class AgendaPalette extends StatelessWidget {
  const AgendaPalette({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final scheme = base.colorScheme.copyWith(
      primary: dark ? const Color(0xff9bc7ff) : const Color(0xff225fa6),
      onPrimary: dark ? const Color(0xff102d4d) : Colors.white,
      primaryContainer: dark
          ? const Color(0xff203f60)
          : const Color(0xffdceaff),
      onPrimaryContainer: dark
          ? const Color(0xffdeecff)
          : const Color(0xff163d6a),
      onSurface: dark ? const Color(0xfff1f4f8) : const Color(0xff17212b),
      onSurfaceVariant: dark
          ? const Color(0xffcbd5e1)
          : const Color(0xff455468),
      surface: dark ? const Color(0xff171c22) : const Color(0xfffafbfd),
      surfaceContainerLow: dark
          ? const Color(0xff1e252e)
          : const Color(0xfff1f4f8),
      surfaceContainer: dark
          ? const Color(0xff242d38)
          : const Color(0xffeaf0f6),
      surfaceContainerHigh: dark
          ? const Color(0xff2c3744)
          : const Color(0xffe2e9f1),
      surfaceTint: dark ? const Color(0xff9bc7ff) : const Color(0xff225fa6),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        textTheme: base.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
      ),
      child: ColoredBox(color: scheme.surface, child: child),
    );
  }
}

/// Opaque blue-grey date bands, distinct from the white/slate calendar surface.
Color agendaDateHeaderFill(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? const Color(0xff283443)
    : const Color(0xffeaf0f7);

/// Keep the provider's hue while reducing the visual weight of event blocks.
Color agendaEventFill(Color calendar, ColorScheme scheme) => Color.alphaBlend(
  calendar.withValues(alpha: scheme.brightness == Brightness.dark ? 0.4 : 0.2),
  scheme.surface,
);

/// Pick the higher-contrast opaque foreground, including mid-tone fills.
Color agendaOnFill(Color fill) =>
    fill.computeLuminance() > 0.179 ? Colors.black : Colors.white;

/// Preserve the calendar hue but ensure readable small text on the surface.
Color agendaAccentText(Color calendar, ColorScheme scheme) {
  final target = scheme.brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
  final opaque = Color.alphaBlend(calendar, scheme.surface);
  for (var step = 0; step <= 10; step++) {
    final candidate = Color.lerp(opaque, target, step / 10)!;
    final a = candidate.computeLuminance();
    final b = scheme.surface.computeLuminance();
    final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    if (ratio >= 4.5) return candidate;
  }
  return target;
}
