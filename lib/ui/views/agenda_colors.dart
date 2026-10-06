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

/// Readable text on [fill].
Color agendaOnFill(Color fill) =>
    fill.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;

/// Calendar colour used as text (the start time in month cells): the raw
/// colour on dark surfaces, darkened on light ones so pale calendars stay
/// legible.
Color agendaAccentText(Color calendar, ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? Color.lerp(calendar, Colors.white, 0.15)!
    : Color.lerp(calendar, Colors.black, 0.4)!;
