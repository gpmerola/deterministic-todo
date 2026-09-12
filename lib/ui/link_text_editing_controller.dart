import 'package:flutter/material.dart';

import '../domain/link_syntax.dart';
import '../domain/quick_add_parser.dart';

class TextLink {
  const TextLink(this.label, this.url, {this.start = 0, this.end = 0});

  final String label;
  final String url;
  final int start;
  final int end;
}

/// Edits Todoist Markdown links as ordinary linked text, hiding raw URLs.
class LinkTextEditingController extends TextEditingController {
  LinkTextEditingController.fromMarkdown(
    String? markdown, {
    this.highlightSmartDates = false,
  }) : links = _extractLinks(markdown ?? ''),
       super(text: _plainText(markdown ?? ''));

  final List<TextLink> links;
  final bool highlightSmartDates;
  static List<TextLink> _extractLinks(String value) {
    final markdown = linkifyPlainUrls(value);
    final pattern = RegExp(
      r'\[([^\]]+)\]\((https?://[^\s)]+)\)',
      caseSensitive: false,
    );
    var removed = 0;
    final result = <TextLink>[];
    for (final match in pattern.allMatches(markdown)) {
      final label = match[1]!;
      final start = match.start - removed;
      result.add(
        TextLink(label, match[2]!, start: start, end: start + label.length),
      );
      removed += match.end - match.start - label.length;
    }
    return result;
  }

  @override
  set value(TextEditingValue next) {
    final old = text;
    if (old != next.text) {
      var prefix = 0;
      while (prefix < old.length &&
          prefix < next.text.length &&
          old[prefix] == next.text[prefix]) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < old.length - prefix &&
          suffix < next.text.length - prefix &&
          old[old.length - suffix - 1] ==
              next.text[next.text.length - suffix - 1]) {
        suffix++;
      }
      var oldEnd = old.length - suffix;
      // A selection replacement must not inherit a link merely because the
      // pasted text happens to share a prefix/suffix with its former label.
      final selected = selection;
      if (selected.isValid &&
          !selected.isCollapsed &&
          next.text.startsWith(old.substring(0, selected.start)) &&
          next.text.endsWith(old.substring(selected.end)) &&
          next.text.length >= selected.start + old.length - selected.end) {
        prefix = selected.start;
        oldEnd = selected.end;
      }
      final delta = next.text.length - old.length;
      final adjusted = <TextLink>[];
      for (final link in links) {
        var start = link.start;
        var end = link.end;
        if (oldEnd <= start) {
          start += delta;
          end += delta;
        } else if (prefix >= end) {
          /* Edit is after this link. */
        } else if (prefix <= start && oldEnd >= end) {
          continue;
        } else if (prefix >= start && oldEnd <= end) {
          end += delta;
        } else {
          continue;
        }
        if (start < end && start >= 0 && end <= next.text.length) {
          adjusted.add(
            TextLink(
              next.text.substring(start, end),
              link.url,
              start: start,
              end: end,
            ),
          );
        }
      }
      links
        ..clear()
        ..addAll(adjusted);
    }
    super.value = next;
  }

  static String _plainText(String value) => markdownToPlainText(value);

  String? get selectedText {
    final range = selection;
    if (!range.isValid || range.isCollapsed) return null;
    return text.substring(range.start, range.end);
  }

  bool addLink(String url) {
    final label = selectedText?.trim();
    final uri = Uri.tryParse(normalizeWebUrl(url));
    if (label == null ||
        label.isEmpty ||
        uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    links.removeWhere(
      (link) => link.start < selection.end && link.end > selection.start,
    );
    links.add(
      TextLink(
        label,
        uri.toString(),
        start: selection.start,
        end: selection.end,
      ),
    );
    notifyListeners();
    return true;
  }

  /// A selection is optional; otherwise insert a readable label at the caret.
  bool insertLink(String url, {String? label}) {
    final uri = Uri.tryParse(normalizeWebUrl(url));
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    final name = label?.trim().isNotEmpty == true
        ? label!.trim()
        : selectedText ?? friendlyLinkLabel(uri.toString());
    if (name.contains('[') ||
        name.contains(']') ||
        uri.toString().contains(')')) {
      return false;
    }
    final range = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final prefix =
        range.start > 0 &&
            !RegExp(r'\s').hasMatch(text[range.start - 1]) &&
            range.isCollapsed
        ? ' '
        : '';
    value = TextEditingValue(
      text: text.replaceRange(range.start, range.end, '$prefix$name'),
      selection: TextSelection.collapsed(
        offset: range.start + prefix.length + name.length,
      ),
    );
    final start = range.start + prefix.length;
    links.removeWhere(
      (link) => link.start < start + name.length && link.end > start,
    );
    links.add(
      TextLink(name, uri.toString(), start: start, end: start + name.length),
    );
    notifyListeners();
    return true;
  }

  bool removeSelectedLink() {
    final label = selectedText?.trim();
    if (label == null || label.isEmpty) return false;
    final before = links.length;
    links.removeWhere(
      (link) => link.start < selection.end && link.end > selection.start,
    );
    if (links.length == before) return false;
    notifyListeners();
    return true;
  }

  void removeLink(TextLink link) {
    links.remove(link);
    notifyListeners();
  }

  void replaceMarkdown(String? markdown) {
    final value = markdown ?? '';
    links.clear();
    text = _plainText(value);
    links.addAll(_extractLinks(value));
    selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!highlightSmartDates) return TextSpan(style: style, text: text);
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

  String toMarkdown() {
    final output = StringBuffer();
    var offset = 0;
    final ordered = [...links]..sort((a, b) => a.start.compareTo(b.start));
    for (final link in ordered) {
      if (link.start < offset || link.end > text.length) continue;
      output
        ..write(linkifyPlainUrls(text.substring(offset, link.start)))
        ..write('[${text.substring(link.start, link.end)}](${link.url})');
      offset = link.end;
    }
    output.write(linkifyPlainUrls(text.substring(offset)));
    return output.toString();
  }
}
