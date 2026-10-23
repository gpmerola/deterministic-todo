import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic events only.
AgendaEntry _event(String id, int hour, int minutes, {String cal = 'g'}) {
  final start = DateTime(2026, 10, 23, hour);
  return AgendaEntry(
    instanceId: id,
    calendarIds: [cal],
    title: id,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    allDay: false,
  );
}

void main() {
  const day = CivilDate(2026, 10, 23);
  const bands = [
    SembleBand(SembleBandKind.available, 10 * 60, 13 * 60),
    SembleBand(SembleBandKind.unavailable, 13 * 60, 14 * 60),
  ];
  bool isVisit(AgendaEntry entry) => entry.calendarIds.contains('semble');

  test('evidenzia solo gli eventi non visite dentro la disponibilità', () {
    final overlaps = sembleOverlaps(
      [
        _event('dentro', 11, 30),
        _event('a cavallo', 9, 90),
        _event('visita', 11, 45, cal: 'semble'),
        _event('nel blocco', 13, 30),
        _event('prima', 8, 60),
        _event('fine esatta', 9, 60),
      ],
      day,
      bands,
      isVisit,
    );
    expect(overlaps, {'dentro', 'a cavallo'});
  });

  test('gli eventi già finiti non sono evidenziati (build 302)', () {
    final overlaps = sembleOverlaps(
      [_event('finito', 10, 30), _event('in corso', 11, 60)],
      day,
      bands,
      isVisit,
      now: DateTime(2026, 10, 23, 11, 30),
    );
    expect(overlaps, {'in corso'});
  });

  test('giornate intere e attività non contano', () {
    final allDay = AgendaEntry(
      instanceId: 'ferie',
      calendarIds: const ['g'],
      title: 'ferie',
      start: DateTime(2026, 10, 23),
      end: DateTime(2026, 10, 24),
      allDay: true,
    );
    expect(sembleOverlaps([allDay], day, bands, isVisit), isEmpty);
    expect(
      sembleOverlaps([_event('x', 11, 30)], day, const [], isVisit),
      isEmpty,
    );
  });
}
