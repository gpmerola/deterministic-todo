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

/// Short label for a pasted URL: the site, plus the last path segment
/// only when it reads as words. Identifiers ("6ac22c33-b194-…"), file
/// names like `index.php` and long segments give just the site: the full
/// IDs took three or four lines in task lists (UI review, build 218).
String friendlyLinkLabel(String url) {
  final uri = Uri.tryParse(normalizeWebUrl(url));
  if (uri == null || uri.host.isEmpty) return url;
  final host = linkHost(uri);
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  if (segments.isEmpty) return host;
  var last = segments.last;
  try {
    last = Uri.decodeComponent(last);
  } on ArgumentError {
    return host;
  }
  last = last.replaceFirst(
    RegExp(r'\.(aspx?|php|html?|jsp)$', caseSensitive: false),
    '',
  );
  final readable = last.replaceAll(RegExp(r'[-_+]+'), ' ').trim();
  const generic = {'index', 'default', 'home', 'view', 'edit', 'main'};
  final looksLikeId =
      RegExp(r'^[0-9a-f -]{8,}$', caseSensitive: false).hasMatch(readable) ||
      RegExp(r'\d').allMatches(readable).length >= 4;
  if (readable.isEmpty ||
      looksLikeId ||
      generic.contains(readable.toLowerCase()) ||
      readable.length > 28) {
    return host;
  }
  return '$host › $readable';
}

/// Host without `www.`.
String linkHost(Uri uri) =>
    uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;

/// Label shown for a stored link: labels the app generated earlier ("site"
/// or "site › …") follow the current [friendlyLinkLabel]; labels the user
/// wrote stay as they are.
String displayLinkLabel(String label, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return label;
  final host = linkHost(uri);
  return label == host || label.startsWith('$host › ')
      ? friendlyLinkLabel(url)
      : label;
}

List<ParsedTextLink> extractMarkdownLinks(String value) => [
  for (final match in _markdownLinkPattern.allMatches(linkifyPlainUrls(value)))
    ParsedTextLink(match.group(1)!, match.group(2)!),
];

String markdownToPlainText(String value) => linkifyPlainUrls(
  value,
).replaceAllMapped(_markdownLinkPattern, (match) => match.group(1)!);
