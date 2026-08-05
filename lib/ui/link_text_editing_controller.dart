import 'package:flutter/material.dart';

import '../domain/link_syntax.dart';

class TextLink {
  const TextLink(this.label, this.url);

  final String label;
  final String url;
}

/// Edits Todoist Markdown links as ordinary linked text, hiding raw URLs.
class LinkTextEditingController extends TextEditingController {
  LinkTextEditingController.fromMarkdown(String? markdown)
    : links = _extractLinks(markdown ?? ''),
      super(text: _plainText(markdown ?? ''));

  final List<TextLink> links;
  static List<TextLink> _extractLinks(String value) => [
    for (final link in extractMarkdownLinks(value))
      TextLink(link.label, link.url),
  ];

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
    links.removeWhere((link) => link.label == label);
    links.add(TextLink(label, uri.toString()));
    notifyListeners();
    return true;
  }

  bool removeSelectedLink() {
    final label = selectedText?.trim();
    if (label == null || label.isEmpty) return false;
    final before = links.length;
    links.removeWhere((link) => link.label == label);
    if (links.length == before) return false;
    notifyListeners();
    return true;
  }

  void removeLink(TextLink link) {
    links.remove(link);
    notifyListeners();
  }

  String toMarkdown() {
    var value = text;
    for (final link in links) {
      final index = value.indexOf(link.label);
      if (index < 0) continue;
      value = value.replaceRange(
        index,
        index + link.label.length,
        '[${link.label}](${link.url})',
      );
    }
    return linkifyPlainUrls(value);
  }
}
