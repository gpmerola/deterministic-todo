import 'package:deterministic_todo/domain/quick_add_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = QuickAddParser();
  final monday = DateTime(2026, 8, 3, 12);

  test('espone la sintassi intelligente da evidenziare', () {
    final matches = parser
        .recognizedSyntax('Fai X oggi alle 18:30')
        .map((match) => match.group(0))
        .toList();

    expect(matches, ['oggi', 'alle 18:30']);
  });

  test('riconosce domani e ora rimuovendoli dal titolo', () {
    final draft = parser.parse('Dentista domani alle 9:30', now: monday);

    expect(draft.title, 'Dentista');
    expect(draft.showDate.toString(), '2026-08-04');
    expect(draft.timeMinutes, 9 * 60 + 30);
  });

  test('riconosce ogni giorno e lo rimuove dal titolo', () {
    final draft = parser.parse('Vitamine ogni giorno', now: monday);

    expect(draft.title, 'Vitamine');
    expect(draft.showDate.toString(), '2026-08-03');
    expect(draft.recurrence, 'calendar:day:1');
  });

  test('riconosce ogni martedì con la prima data utile', () {
    final draft = parser.parse('Allenamento ogni martedì', now: monday);

    expect(draft.title, 'Allenamento');
    expect(draft.showDate.toString(), '2026-08-04');
    expect(draft.recurrence, 'calendar:week:1');
  });

  test('riconosce intervalli ogni quattro giorni', () {
    final draft = parser.parse('Controllo ogni 4 giorni', now: monday);

    expect(draft.title, 'Controllo');
    expect(draft.recurrence, 'calendar:day:4');
  });

  test('riconosce il prossimo giorno della settimana', () {
    final draft = parser.parse('Chiamare Luca venerdì', now: monday);

    expect(draft.title, 'Chiamare Luca');
    expect(draft.showDate.toString(), '2026-08-07');
  });

  test('una data numerica passata senza anno passa all anno dopo', () {
    final draft = parser.parse('Rinnovo il 02/08', now: monday);

    expect(draft.title, 'Rinnovo');
    expect(draft.showDate.toString(), '2027-08-02');
  });

  test('l ora senza data pianifica oggi', () {
    final draft = parser.parse('Telefonata alle 18', now: monday);

    expect(draft.title, 'Telefonata');
    expect(draft.showDate.toString(), '2026-08-03');
    expect(draft.timeMinutes, 18 * 60);
  });

  test('riconosce una data italiana con mese in lettere', () {
    final draft = parser.parse('Assicurazione 12 agosto', now: monday);

    expect(draft.title, 'Assicurazione');
    expect(draft.showDate.toString(), '2026-08-12');
  });

  test('rifiuta date impossibili', () {
    expect(
      () => parser.parse('Evento 31/02', now: monday),
      throwsFormatException,
    );
  });
}
