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
  final priorityPattern = RegExp(
    r'(^|\s)p([1-4])(?=\s|$)',
    caseSensitive: false,
  );
  final priorityMatch = priorityPattern.firstMatch(text);
  if (priorityMatch != null) {
    priority = 5 - int.parse(priorityMatch.group(2)!);
    text = text.replaceRange(
      priorityMatch.start,
      priorityMatch.end,
      priorityMatch.group(1)!,
    );
  }
  final orderedProjects = projectsByName.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  final lower = text.toLowerCase();
  for (final entry in orderedProjects) {
    final marker = '#${entry.key.toLowerCase()}';
    final index = lower.indexOf(marker);
    if (index < 0) continue;
    final end = index + marker.length;
    final validEnd = end == text.length || RegExp(r'\s').hasMatch(text[end]);
    if (!validEnd) continue;
    projectId = entry.value;
    text = text.replaceRange(index, end, ' ');
    break;
  }
  return QuickAddMetadata(
    text: text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    priority: priority,
    projectId: projectId,
  );
}
