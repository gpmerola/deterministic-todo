import 'package:deterministic_todo/domain/quick_add_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = QuickAddParser();
  final monday = DateTime(2026, 8, 3, 12);

  test('espone la sintassi intelligente da evidenziare', () {
    final matches = parser
        .recognizedSyntax('Fai X oggi')
        .map((match) => match.group(0))
        .toList();

    expect(matches, ['oggi']);
  });

  test('riconosce domani senza interpretare un orario', () {
    final draft = parser.parse('Dentista domani alle 9:30', now: monday);

    expect(draft.title, 'Dentista alle 9:30');
    expect(draft.showDate.toString(), '2026-08-04');
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

  test('riconosce un giorno fisso di ogni mese', () {
    final draft = parser.parse('Pagamento ogni 3 del mese', now: monday);

    expect(draft.title, 'Pagamento');
    expect(draft.showDate.toString(), '2026-08-03');
    expect(draft.recurrence, 'calendar:month:1');
  });

  test('riconosce il terzo martedì di ogni mese', () {
    final draft = parser.parse('Controllo ogni terzo martedì', now: monday);

    expect(draft.title, 'Controllo');
    expect(draft.showDate.toString(), '2026-08-18');
    expect(draft.recurrence, 'calendar:monthWeekday:1');
  });

  test('riconosce una ricorrenza annuale con giorno e mese', () {
    final draft = parser.parse('Rinnovo ogni 3 luglio', now: monday);

    expect(draft.title, 'Rinnovo');
    expect(draft.showDate.toString(), '2027-07-03');
    expect(draft.recurrence, 'calendar:year:1');
  });

  test('riconosce giorni feriali e ultimo venerdì', () {
    final weekday = parser.parse('Email ogni giorno feriale', now: monday);
    final lastFriday = parser.parse(
      'Report ogni ultimo venerdì del mese',
      now: monday,
    );

    expect(weekday.recurrence, 'calendar:weekday:1');
    expect(lastFriday.showDate.toString(), '2026-08-28');
    expect(lastFriday.recurrence, 'calendar:monthLastWeekday:1');
  });

  test('riconosce fine mese e ricorrenza dopo completamento', () {
    final end = parser.parse('Chiudi conti fine mese', now: monday);
    final after = parser.parse(
      'Cambiare filtro ogni 3 giorni dopo il completamento',
      now: monday,
    );

    expect(end.title, 'Chiudi conti');
    expect(end.showDate.toString(), '2026-08-31');
    expect(after.title, 'Cambiare filtro');
    expect(after.recurrence, 'afterCompletion:day:3');
  });

  test('riconosce stasera e distanze relative', () {
    final tonight = parser.parse('Film stasera', now: monday);
    final later = parser.parse('Richiama fra 2 settimane', now: monday);

    expect(tonight.showDate.toString(), '2026-08-03');
    expect(later.title, 'Richiama');
    expect(later.showDate.toString(), '2026-08-17');
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

  test('un orario resta testo normale', () {
    final draft = parser.parse('Telefonata domani alle 18', now: monday);
    final matches = parser
        .recognizedSyntax('Telefonata domani alle 18')
        .map((match) => match.group(0))
        .toList();

    expect(draft.title, 'Telefonata alle 18');
    expect(draft.showDate.toString(), '2026-08-04');
    expect(matches, ['domani']);
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
