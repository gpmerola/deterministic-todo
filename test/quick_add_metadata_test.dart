import 'package:deterministic_todo/domain/quick_add_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estrae progetto e priorità Todoist-like dalla stessa riga', () {
    final parsed = parseQuickAddMetadata(
      'Finisci paper #PhD p1 domani',
      defaultPriority: 1,
      projectsByName: const {'PhD': 'project-phd'},
    );

    expect(parsed.text, 'Finisci paper domani');
    expect(parsed.priority, 4);
    expect(parsed.projectId, 'project-phd');
  });

  test('conserva le ultime preferenze in assenza di sintassi esplicita', () {
    final parsed = parseQuickAddMetadata(
      'Compra latte',
      defaultPriority: 3,
      defaultProjectId: 'casa',
      projectsByName: const {},
    );

    expect(parsed.priority, 3);
    expect(parsed.projectId, 'casa');
  });
}
