import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/link_syntax.dart';

/// Renders Todoist-style Markdown links without exposing their raw URLs.
class TodoistLinkText extends StatefulWidget {
  const TodoistLinkText(
    this.value, {
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    super.key,
  });

  final String value;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<TodoistLinkText> createState() => _TodoistLinkTextState();
}

class _TodoistLinkTextState extends State<TodoistLinkText> {
  static final linkPattern = RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)');
  final recognizers = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(covariant TodoistLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _disposeRecognizers();
  }

  void _disposeRecognizers() {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
    recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var offset = 0;
    final displayValue = linkifyPlainUrls(widget.value);
    for (final match in linkPattern.allMatches(displayValue)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: displayValue.substring(offset, match.start)));
      }
      final uri = Uri.parse(match.group(2)!);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
      recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: match.group(1),
          recognizer: recognizer,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < displayValue.length) {
      spans.add(TextSpan(text: displayValue.substring(offset)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
