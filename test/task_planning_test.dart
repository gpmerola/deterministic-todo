import 'package:deterministic_todo/domain/task_planning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reference = DateTime(2026, 8, 31, 12);

  test('senza data pianifica implicitamente per oggi', () {
    final draft = parsePlannedQuickTask('Comprare il pane', now: reference);

    expect(draft.title, 'Comprare il pane');
    expect(draft.showDate.toString(), '2026-08-31');
  });

  test('una data valida esplicita resta autorevole', () {
    final draft = parsePlannedQuickTask('Dentista domani', now: reference);

    expect(draft.title, 'Dentista');
    expect(draft.showDate.toString(), '2026-09-01');
  });

  test('una data impossibile ricade su oggi senza perdere il titolo', () {
    final draft = parsePlannedQuickTask(
      'Promemoria 31 febbraio',
      now: reference,
    );

    expect(draft.title, 'Promemoria 31 febbraio');
    expect(draft.showDate.toString(), '2026-08-31');
  });

  test('il campo data vuoto o invalido ricade su oggi', () {
    expect(plannedDateOrToday('', now: reference).toString(), '2026-08-31');
    expect(
      plannedDateOrToday('non-una-data', now: reference).toString(),
      '2026-08-31',
    );
  });
}
