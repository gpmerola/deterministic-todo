import 'package:flutter/material.dart';

/// Event fill for a calendar colour. On dark surfaces the raw provider
/// colours (lime, cyan, red) are loud, so they are blended half into the
/// surface, as calendar apps do in dark mode (UI review, build 218).
Color agendaEventFill(Color calendar, ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
    ? Color.alphaBlend(calendar.withValues(alpha: 0.5), scheme.surface)
    : calendar;

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
