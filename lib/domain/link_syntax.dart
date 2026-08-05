class ParsedTextLink {
  const ParsedTextLink(this.label, this.url);

  final String label;
  final String url;
}

final RegExp _markdownLinkPattern = RegExp(
  r'\[([^\]]+)\]\((https?://[^\s)]+)\)',
  caseSensitive: false,
);
final RegExp _plainLinkPattern = RegExp(
  r'(?<!\]\()(?:https?://|www\.)[^\s<>]+',
  caseSensitive: false,
);

String normalizeWebUrl(String value) {
  final trimmed = value.trim();
  return trimmed.toLowerCase().startsWith('www.')
      ? 'https://$trimmed'
      : trimmed;
}

String linkifyPlainUrls(String value) {
  final output = StringBuffer();
  var offset = 0;
  for (final markdown in _markdownLinkPattern.allMatches(value)) {
    output
      ..write(_linkifyGap(value.substring(offset, markdown.start)))
      ..write(markdown.group(0));
    offset = markdown.end;
  }
  output.write(_linkifyGap(value.substring(offset)));
  return output.toString();
}

String _linkifyGap(String value) =>
    value.replaceAllMapped(_plainLinkPattern, (match) {
      var label = match.group(0)!;
      var suffix = '';
      while (label.isNotEmpty && '.,;:!?'.contains(label[label.length - 1])) {
        suffix = '${label[label.length - 1]}$suffix';
        label = label.substring(0, label.length - 1);
      }
      if (label.isEmpty) return match.group(0)!;
      return '[$label](${normalizeWebUrl(label)})$suffix';
    });

List<ParsedTextLink> extractMarkdownLinks(String value) => [
  for (final match in _markdownLinkPattern.allMatches(linkifyPlainUrls(value)))
    ParsedTextLink(match.group(1)!, match.group(2)!),
];

String markdownToPlainText(String value) => linkifyPlainUrls(
  value,
).replaceAllMapped(_markdownLinkPattern, (match) => match.group(1)!);
