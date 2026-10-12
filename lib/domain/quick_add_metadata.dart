class QuickAddMetadata {
  const QuickAddMetadata({
    required this.text,
    required this.priority,
    this.projectId,
  });

  final String text;
  final int priority;
  final String? projectId;
}

QuickAddMetadata parseQuickAddMetadata(
  String source, {
  required int defaultPriority,
  String? defaultProjectId,
  required Map<String, String> projectsByName,
}) {
  var text = source;
  var priority = defaultPriority;
  String? projectId = defaultProjectId;
  final priorityMatch = _priorityPattern.firstMatch(text);
  if (priorityMatch != null) {
    priority = 5 - int.parse(priorityMatch.group(2)!);
    text = text.replaceRange(
      priorityMatch.start,
      priorityMatch.end,
      priorityMatch.group(1)!,
    );
  }
  final projectMatch = _projectMatch(text, projectsByName);
  if (projectMatch != null) {
    projectId = projectMatch.id;
    text = text.replaceRange(projectMatch.start, projectMatch.end, ' ');
  }
  return QuickAddMetadata(
    text: text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    priority: priority,
    projectId: projectId,
  );
}

final _priorityPattern = RegExp(
  r'(^|\s)p([1-4])(?=\s|$)',
  caseSensitive: false,
);

({int start, int end, String id})? _projectMatch(
  String text,
  Map<String, String> projectsByName,
) {
  final ordered = projectsByName.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  final lower = text.toLowerCase();
  for (final entry in ordered) {
    final marker = '#${entry.key.toLowerCase()}';
    final index = lower.indexOf(marker);
    if (index < 0) continue;
    final end = index + marker.length;
    if (end != text.length && !RegExp(r'\s').hasMatch(text[end])) continue;
    return (start: index, end: end, id: entry.value);
  }
  return null;
}

/// A menu selection edits the recognised token, leaving dates and prose intact.
/// Without a token the composer stores the selection as its explicit default.
String selectQuickAddPriority(String source, int priority) {
  final match = _priorityPattern.firstMatch(source);
  if (match == null) return source;
  return source.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}p${5 - priority}',
  );
}

String selectQuickAddProject(
  String source, {
  required String? projectId,
  required Map<String, String> projectsByName,
}) {
  final match = _projectMatch(source, projectsByName);
  if (match == null) return source;
  final name = projectsByName.entries
      .where((e) => e.value == projectId)
      .firstOrNull
      ?.key;
  return source.replaceRange(
    match.start,
    match.end,
    name == null ? '' : '#$name',
  );
}
