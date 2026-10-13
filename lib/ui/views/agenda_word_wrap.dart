import 'package:flutter/material.dart';

/// Lines of [text] broken only between words. A word wider than the line
/// stays whole on its own line, to be ellipsized, instead of being split
/// across lines as Flutter does ("Mrcpscy / h paper", UI review build 218).
List<String> wrapWords(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler scaler,
) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  double widthOf(String value) {
    painter
      ..text = TextSpan(text: value, style: style)
      ..layout();
    return painter.width;
  }

  final lines = <String>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final candidate = current.isEmpty ? word : '$current $word';
    if (current.isEmpty || widthOf(candidate) <= maxWidth) {
      current = candidate;
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  painter.dispose();
  return lines;
}
