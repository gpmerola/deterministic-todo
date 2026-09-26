import 'package:flutter/material.dart';

import '../domain/quick_add_parser.dart';

/// Highlights only syntax that the parser will remove and convert to a date.
class SmartDateTextController extends TextEditingController {
  SmartDateTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    const parser = QuickAddParser();
    try {
      parser.parse(text);
    } on FormatException {
      return TextSpan(style: style, text: text);
    }
    final matches = parser.recognizedSyntax(text).toList();
    if (matches.isEmpty) return TextSpan(style: style, text: text);
    final highlighted = style?.copyWith(
      color: Theme.of(context).colorScheme.onPrimaryContainer,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (cursor < match.start) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: highlighted,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
