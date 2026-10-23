import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/semble_conflicts.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  group('controllo in background (build 304)', () {
    // Synthetic weekly rule: Fridays 10:00–13:00 London.
    final rule = SembleRule.fromJson({
      'id': 'r',
      'unavailability': false,
      'startDate': '2026-10-02',
      'startTime': '10:00',
      'endTime': '13:00',
      'recurrence': {
        'frequency': 'weekly',
        'interval': 1,
        'daysOfTheWeek': [5],
      },
    })!;

    test('la regola sopravvive al salvataggio in cache', () {
      final copy = SembleRule.fromJson(rule.toJson())!;
      expect(copy.toJson(), rule.toJson());
      expect(copy.appliesOn(day), isTrue);
      expect(copy.appliesOn(const CivilDate(2026, 10, 22)), isFalse);
    });

    test('solo eventi futuri, non visite, in orario prenotabile', () {
      final found = sembleConflicts(
        entries: [
          _event('dentro', 11, 30),
          _event('visita', 12, 30, cal: 'semble'),
          _event('fuori', 15, 30),
          _event('passato', 10, 15),
        ],
        rules: [rule],
        first: const CivilDate(2026, 10, 20),
        last: const CivilDate(2026, 11, 20),
        now: DateTime(2026, 10, 23, 10, 30),
        until: DateTime(2026, 11, 6),
        isVisit: isVisit,
        zoneShift: (_) => 0,
      );
      expect(found.map((e) => e.instanceId), ['dentro']);
      final plan = sembleConflictPlan(found).single;
      expect(plan.keys.toSet(), {'id', 'start', 'end'});
      expect('$plan', isNot(contains('dentro')));
    });

    test('fuori dalla finestra letta non segnala nulla', () {
      final found = sembleConflicts(
        entries: [_event('dentro', 11, 30)],
        rules: [rule],
        first: const CivilDate(2026, 10, 24),
        last: const CivilDate(2026, 11, 20),
        now: DateTime(2026, 10, 23, 9),
        until: DateTime(2026, 10, 24),
        isVisit: isVisit,
        zoneShift: (_) => 0,
      );
      expect(found, isEmpty);
    });

    test('cache delle regole e interruttore avvisi', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = SembleSettings();
      expect(await settings.cachedRules(), isNull);
      expect(await settings.conflictAlerts(), isTrue);
      await settings.saveRules(
        [rule],
        const CivilDate(2026, 10, 1),
        const CivilDate(2026, 11, 30),
      );
      final cache = (await settings.cachedRules())!;
      expect(cache.first, const CivilDate(2026, 10, 1));
      expect(cache.last, const CivilDate(2026, 11, 30));
      expect(cache.rules.single.toJson(), rule.toJson());
      await settings.setConflictAlerts(false);
      expect(await settings.conflictAlerts(), isFalse);
      await settings.clear();
      expect(await settings.cachedRules(), isNull);
    });
  });
}
