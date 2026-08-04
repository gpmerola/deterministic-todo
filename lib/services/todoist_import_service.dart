import 'dart:convert';

class TodoistImportPreview {
  const TodoistImportPreview({
    required this.projects,
    required this.sections,
    required this.activeTasks,
    required this.scheduledTasks,
    required this.recurringTasks,
    required this.unsupportedRecurrences,
    required this.priorityCounts,
  });

  final int projects;
  final int sections;
  final int activeTasks;
  final int scheduledTasks;
  final int recurringTasks;
  final List<String> unsupportedRecurrences;
  final Map<int, int> priorityCounts;

  bool get canImport => unsupportedRecurrences.isEmpty;
}

/// Legge un export Sync Todoist senza scrivere alcun dato. L'importatore usa
/// questa anteprima come gate: nessun formato ambiguo passa silenziosamente.
class TodoistImportService {
  const TodoistImportService();

  TodoistImportPreview preview(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Export Todoist non valido');
    }
    final projects = _list(decoded, 'projects');
    final sections = _list(decoded, 'sections');
    final items = _list(decoded, 'items');
    final active = items.where((item) {
      return item['is_deleted'] != true && item['checked'] != true;
    }).toList();
    final priorityCounts = <int, int>{};
    var scheduled = 0;
    var recurring = 0;
    final unsupported = <String>{};
    for (final item in active) {
      final priority = item['priority'];
      if (priority is! int || priority < 1 || priority > 4) {
        throw const FormatException('Priorità Todoist non valida');
      }
      priorityCounts.update(priority, (count) => count + 1, ifAbsent: () => 1);
      final due = item['due'];
      if (due == null) continue;
      if (due is! Map<String, dynamic> || due['date'] is! String) {
        throw const FormatException('Data Todoist non valida');
      }
      scheduled++;
      if (due['is_recurring'] == true) {
        recurring++;
        final expression = (due['string'] as String? ?? '').trim();
        if (!_isSupportedRecurrence(expression)) unsupported.add(expression);
      }
    }
    return TodoistImportPreview(
      projects: projects.where((row) => row['is_deleted'] != true).length,
      sections: sections.where((row) => row['is_deleted'] != true).length,
      activeTasks: active.length,
      scheduledTasks: scheduled,
      recurringTasks: recurring,
      unsupportedRecurrences: unsupported.toList()..sort(),
      priorityCounts: priorityCounts,
    );
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> root, String key) {
    final value = root[key];
    if (value is! List) throw FormatException('Campo Todoist $key mancante');
    return value.map((row) {
      if (row is! Map) throw FormatException('Record Todoist $key non valido');
      return row.cast<String, dynamic>();
    }).toList();
  }

  bool _isSupportedRecurrence(String value) => RegExp(
    r'^ogni\s+(?:(?:\d+\s+)?(?:giorno|giorni|settimana|settimane|mese|mesi|anno|anni)|(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)|(?:primo|secondo|terzo|quarto|quinto)\s+(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?|[0-3]?\d(?:\s+del\s+mese|\s+(?:gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)))$',
    caseSensitive: false,
  ).hasMatch(value);
}
