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
      final url = normalizeWebUrl(label);
      return '[${friendlyLinkLabel(url)}]($url)$suffix';
    });

String friendlyLinkLabel(String url) {
  final uri = Uri.tryParse(normalizeWebUrl(url));
  if (uri == null || uri.host.isEmpty) return url;
  final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  final last = segments.isEmpty ? null : segments.last;
  if (last == null || RegExp(r'^\d+$').hasMatch(last)) return host;
  final readable = Uri.decodeComponent(last).replaceAll(RegExp(r'[-_]+'), ' ');
  return readable.isEmpty ? host : '$host › $readable';
}

List<ParsedTextLink> extractMarkdownLinks(String value) => [
  for (final match in _markdownLinkPattern.allMatches(linkifyPlainUrls(value)))
    ParsedTextLink(match.group(1)!, match.group(2)!),
];

String markdownToPlainText(String value) => linkifyPlainUrls(
  value,
).replaceAllMapped(_markdownLinkPattern, (match) => match.group(1)!);
