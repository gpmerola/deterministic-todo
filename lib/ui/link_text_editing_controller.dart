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
    var removed = 0;
    final result = <TextLink>[];
    for (final match in markdownLinkPattern.allMatches(markdown)) {
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
      final newEnd = oldEnd + delta;
      final inserted = next.text.substring(prefix, newEnd);
      final adjusted = <TextLink>[];
      final dropped = <TextLink>[];
      // A link that the previous change removed and this one types back,
      // identical and in the same place, is restored (see [_recentlyDropped]).
      for (final link in _recentlyDropped) {
        final at = link.start;
        if (oldEnd == prefix &&
            at >= prefix &&
            at + link.label.length <= newEnd &&
            next.text.substring(at, at + link.label.length) == link.label) {
          adjusted.add(
            TextLink(
              link.label,
              link.url,
              start: at,
              end: at + link.label.length,
            ),
          );
        }
      }
      for (final link in links) {
        var start = link.start;
        var end = link.end;
        if (oldEnd <= start) {
          start += delta;
          end += delta;
        } else if (prefix >= end) {
          /* Edit is after this link. */
        } else if (prefix <= start && oldEnd >= end) {
          // The change rewrote the whole label. Android keyboards often
          // rewrite the word around the caret even to add one space: keep
          // the link while its label is still there, unchanged.
          final at = _closestOccurrence(inserted, link.label, start - prefix);
          if (at < 0) {
            if (link.label.length > 1) {
              dropped.add(
                TextLink(link.label, link.url, start: prefix, end: prefix),
              );
            }
            continue;
          }
          start = prefix + at;
          end = start + link.label.length;
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
      adjusted.sort((a, b) => a.start.compareTo(b.start));
      final kept = <TextLink>[];
      for (final link in adjusted) {
        if (kept.isEmpty || kept.last.end <= link.start) kept.add(link);
      }
      links
        ..clear()
        ..addAll(kept);
      _recentlyDropped = dropped;
    }
    super.value = next;
  }

  /// Links removed by the last text change, kept for one more change: some
  /// keyboards delete a word and type it again in two steps, which must not
  /// turn a link back into plain text. Explicit removals never land here.
  List<TextLink> _recentlyDropped = const [];

  static int _closestOccurrence(String text, String label, int preferred) {
    if (label.isEmpty) return -1;
    var best = -1;
    for (
      var at = text.indexOf(label);
      at >= 0;
      at = text.indexOf(label, at + 1)
    ) {
      if (best < 0 || (at - preferred).abs() < (best - preferred).abs()) {
        best = at;
      }
    }
    return best;
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
    _recentlyDropped = const [];
    notifyListeners();
    return true;
  }

  void removeLink(TextLink link) {
    links.remove(link);
    _recentlyDropped = const [];
    notifyListeners();
  }

  void replaceMarkdown(String? markdown) {
    final value = markdown ?? '';
    links.clear();
    _recentlyDropped = const [];
    text = _plainText(value);
    links.addAll(_extractLinks(value));
    selection = TextSelection.collapsed(offset: text.length);
  }

  /// Linked words are underlined while editing too (from build 325): they
  /// looked like plain text, so a kept link seemed lost.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final dates = <TextRange>[];
    if (highlightSmartDates) {
      const parser = QuickAddParser();
      try {
        parser.parse(text);
        for (final match in parser.recognizedSyntax(text)) {
          dates.add(TextRange(start: match.start, end: match.end));
        }
      } on FormatException {
        dates.clear();
      }
    }
    final linked = [
      for (final link in links)
        if (link.start >= 0 && link.end <= text.length && link.start < link.end)
          TextRange(start: link.start, end: link.end),
    ];
    if (dates.isEmpty && linked.isEmpty) {
      return TextSpan(style: style, text: text);
    }
    final scheme = Theme.of(context).colorScheme;
    final dateStyle = TextStyle(
      color: scheme.onPrimaryContainer,
      backgroundColor: scheme.primaryContainer,
      fontWeight: FontWeight.w600,
    );
    final linkStyle = TextStyle(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );
    final cuts = <int>{0, text.length};
    for (final range in [...dates, ...linked]) {
      cuts
        ..add(range.start)
        ..add(range.end);
    }
    final ordered = cuts.where((cut) => cut <= text.length).toList()..sort();
    bool inside(List<TextRange> ranges, int at) =>
        ranges.any((range) => range.start <= at && at < range.end);
    final spans = <InlineSpan>[];
    for (var index = 0; index + 1 < ordered.length; index++) {
      final from = ordered[index];
      final to = ordered[index + 1];
      if (from == to) continue;
      TextStyle? segment;
      if (inside(dates, from)) segment = dateStyle;
      if (inside(linked, from)) {
        segment = segment == null ? linkStyle : segment.merge(linkStyle);
      }
      spans.add(TextSpan(text: text.substring(from, to), style: segment));
    }
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
