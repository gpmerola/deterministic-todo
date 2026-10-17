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

  test('menu priority edits only the recognised token and preserves date', () {
    expect(
      selectQuickAddPriority('Leggi P1 domani #Casa', 3),
      'Leggi p2 domani #Casa',
    );
    expect(selectQuickAddPriority('Leggi domani', 4), 'Leggi domani');
    expect(selectQuickAddPriority('Leggi p1 domani', 1), 'Leggi p4 domani');
  });

  test('project menu replaces or removes only the recognised project', () {
    const projects = {'Casa': 'a', 'Casa nuova': 'b', 'Lavoro': 'c'};
    expect(
      selectQuickAddProject(
        'Leggi #Casa nuova p1 domani',
        projectId: 'c',
        projectsByName: projects,
      ),
      'Leggi #Lavoro p1 domani',
    );
    expect(
      selectQuickAddProject(
        'Leggi #Casa p1 domani',
        projectId: null,
        projectsByName: projects,
      ),
      'Leggi  p1 domani',
    );
    expect(
      selectQuickAddProject(
        'Leggi #Sconosciuto p1 domani',
        projectId: 'c',
        projectsByName: projects,
      ),
      'Leggi #Sconosciuto p1 domani',
    );
  });
}
