import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/private_earnings.dart';
import 'package:deterministic_todo/domain/semble_availability.dart';
import 'package:deterministic_todo/domain/semble_bookings.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/services/private_earnings_service.dart';
import 'package:deterministic_todo/services/semble_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Synthetic bookings shaped like Semble's: clinic wall-clock digits
// labelled Z; no real data.
String semble(DateTime instant) {
  final utc = instant.toUtc();
  final digits = londonSummerTime(utc)
      ? utc.add(const Duration(hours: 1))
      : utc;
  return digits.toIso8601String();
}

Map<String, Object?> booking(
  DateTime start, {
  int minutes = 30,
  bool deleted = false,
  String doctor = 'Dr Test Merola',
  String type = 'Follow-up 30',
  bool arrived = false,
  bool dna = false,
}) => {
  'start': semble(start),
  'end': semble(start.add(Duration(minutes: minutes))),
  'deleted': deleted,
  'doctorName': doctor,
  'appointment': {'title': type},
  'bookingJourney': {
    'arrived': arrived ? semble(start) : null,
    'consultation': null,
    'departed': null,
    'dna': dna ? semble(start) : null,
  },
};

SembleBooking parsed(Map<String, Object?> json) =>
    SembleBooking.fromJson(json)!;

AgendaEntry visit(String title, DateTime start, {String id = 'v'}) =>
    AgendaEntry(
      instanceId: id,
      calendarIds: const ['semble'],
      title: title,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      allDay: false,
    );

final at10 = DateTime(2026, 10, 5, 10);

void main() {
  group('esiti', () {
    test('il percorso in reception dà l esito', () {
      expect(
        parsed(booking(at10, arrived: true)).outcome,
        SembleOutcome.attended,
      );
      expect(parsed(booking(at10, dna: true)).outcome, SembleOutcome.dna);
      expect(
        parsed(booking(at10, deleted: true)).outcome,
        SembleOutcome.cancelled,
      );
      expect(parsed(booking(at10)).outcome, SembleOutcome.unknown);
      expect(parsed(booking(at10)).start, at10);
      expect(SembleBooking.fromJson({'start': null}), isNull);
    });

    test('le cifre di Semble sono ora di Londra, anche con Z', () {
      // 10:00 in London is 09:00 UTC in BST and 10:00 UTC in winter; the
      // phone shows it in its own zone (11:00 in Rome).
      final summer = DateTime.utc(2026, 10, 23, 9).toLocal();
      for (final text in [
        '2026-10-23T10:00:00.000Z',
        '2026-10-23T10:00:00.000',
        '2026-10-23 10:00:00',
        '${DateTime.utc(2026, 10, 23, 10).millisecondsSinceEpoch}',
      ]) {
        expect(
          SembleBooking.fromJson({'start': text})!.start,
          summer,
          reason: text,
        );
      }
      expect(
        SembleBooking.fromJson({'start': '2026-11-10T10:00:00.000Z'})!.start,
        DateTime.utc(2026, 11, 10, 10).toLocal(),
      );
      // Around the changes (25 October 2026, 28 March 2027 at 01:00 UTC).
      expect(
        SembleBooking.fromJson({'start': '2026-10-25T00:30:00.000Z'})!.start,
        DateTime.utc(2026, 10, 24, 23, 30).toLocal(),
      );
      expect(
        SembleBooking.fromJson({'start': '2026-10-25T09:00:00.000Z'})!.start,
        DateTime.utc(2026, 10, 25, 9).toLocal(),
      );
      expect(
        SembleBooking.fromJson({'start': '2027-03-28T09:00:00.000Z'})!.start,
        DateTime.utc(2027, 3, 28, 8).toLocal(),
      );
      expect(
        SembleBooking.fromJson({'start': '2027-03-27T09:00:00.000Z'})!.start,
        DateTime.utc(2027, 3, 27, 9).toLocal(),
      );
      // A real offset is still an instant.
      expect(
        SembleBooking.fromJson({'start': '2026-10-23T11:00:00+01:00'})!.start,
        DateTime.utc(2026, 10, 23, 10).toLocal(),
      );
    });

    test('abbinamento per minuto, tipo di visita e cognome', () {
      final entry = visit('Follow-up 30 · Mario R.', at10);
      // Same minute, other clinician: excluded by name.
      expect(
        sembleOutcomeFor(entry, [
          parsed(booking(at10, dna: true, doctor: 'Dr Other')),
        ], surname: 'Merola'),
        SembleOutcome.unknown,
      );
      // Two bookings at 10:00 of different types: the title decides.
      expect(
        sembleOutcomeFor(entry, [
          parsed(booking(at10, dna: true, type: 'Prima visita')),
          parsed(booking(at10, arrived: true)),
        ]),
        SembleOutcome.attended,
      );
      // A deleted booking and its live replacement: the live one counts.
      expect(
        sembleOutcomeFor(entry, [
          parsed(booking(at10, deleted: true)),
          parsed(booking(at10, dna: true)),
        ]),
        SembleOutcome.dna,
      );
      // Disagreeing bookings that cannot be told apart: never guessed.
      expect(
        sembleOutcomeFor(entry, [
          parsed(booking(at10, dna: true, type: 'X')),
          parsed(booking(at10, arrived: true, type: 'Y')),
        ]),
        SembleOutcome.unknown,
      );
      expect(sembleOutcomeFor(entry, const []), SembleOutcome.unknown);
      expect(
        sembleOutcomeFor(entry, [
          parsed(booking(at10.add(const Duration(minutes: 1)), dna: true)),
        ]),
        SembleOutcome.unknown,
      );
    });

    test('DNA e cancellate escono dai totali e restano visibili', () {
      final now = DateTime(2026, 10, 12, 18);
      final dna = visit('Follow-up 30', at10, id: 'a');
      final done = visit(
        'Follow-up 30',
        at10.add(const Duration(days: 1)),
        id: 'b',
      );
      final gone = visit(
        'Follow-up 30',
        at10.add(const Duration(days: 2)),
        id: 'c',
      );
      final outcomes = {
        'a': SembleOutcome.dna,
        'b': SembleOutcome.attended,
        'c': SembleOutcome.cancelled,
      };
      final result = estimatePrivateEarnings(
        [dna, done, gone],
        now,
        outcome: (entry) => outcomes[entry.instanceId]!,
      );
      expect(result.pence, PrivateFee.followUp30.pence);
      expect(result.dnaCounts, {PrivateFee.followUp30: 1});
      expect(result.dnaPence, PrivateFee.followUp30.pence);
      expect(result.sembleCancelled, 1);
      expect(result.sembleMatched, (matched: 3, checked: 3));
      final plain = estimatePrivateEarnings([dna, done, gone], now);
      expect(plain.pence, 3 * PrivateFee.followUp30.pence);
      expect(plain.sembleMatched, isNull);
    });
  });

  test('stima dalle prenotazioni: tipi Semble, copie del calendario tolte', () {
    final now = DateTime(2026, 10, 23, 12);
    final day = DateTime(2026, 10, 23);
    DateTime h(int hour, [int minute = 0]) =>
        day.add(Duration(hours: hour, minutes: minute));
    Map<String, Object?> typed(
      DateTime start,
      int minutes,
      String type, {
      bool deleted = false,
      bool dna = false,
      bool arrived = false,
    }) => booking(
      start,
      minutes: minutes,
      type: type,
      deleted: deleted,
      dna: dna,
      arrived: arrived,
    );
    final bookings = [
      typed(h(10), 30, 'Follow-up Consultation (15 min)', arrived: true),
      typed(h(11), 45, 'Follow-up Consultation - 30 min (PLE)', dna: true),
      typed(h(17, 30), 75, 'Initial Consultation (Adult) (60 min)'),
      // Moved in place: the deleted copy is not a cancellation.
      typed(
        h(17, 30),
        75,
        'Initial Consultation (Adult) (60 min)',
        deleted: true,
      ),
      typed(h(19), 30, 'Follow-up Consultation (15 min)', deleted: true),
    ].map(parsed).toList();
    AgendaEntry entry(String id, String calendar, String title, DateTime at) =>
        AgendaEntry(
          instanceId: id,
          calendarIds: [calendar],
          title: title,
          start: at,
          end: at.add(const Duration(minutes: 30)),
          allDay: false,
        );
    final result = estimateWithSembleBookings(
      calendarEntries: [
        entry('ical', 'semble', 'Follow-up 15', h(10)),
        // A copy of a booking in a calendar named otherwise.
        entry('opuk', 'opuk', 'Prima visita 60 min', h(17, 30)),
        entry('heydoc', 'heydoc', 'Follow-up 15 min', h(14)),
      ],
      bookings: bookings,
      sembleCalendarIds: const {'semble'},
      now: now,
    );
    expect(result.counts, {PrivateFee.followUp15: 1});
    expect(result.scheduledCounts, {
      PrivateFee.initial: 1,
      PrivateFee.followUp15: 1,
    });
    expect(result.dnaCounts, {PrivateFee.followUp30: 1});
    expect(result.sembleCancelled, 1);
    expect(result.sembleVisits, 4);
  });

  group('client', () {
    test(
      'legge solo campi senza pazienti, filtra per cognome e pagina',
      () async {
        final queries = <String>[];
        final client = SembleClient(
          client: MockClient((request) async {
            final query = (jsonDecode(request.body) as Map)['query'] as String;
            queries.add(query);
            final page = queries.length;
            return http.Response(
              jsonEncode({
                'data': {
                  'bookings': {
                    'data': [
                      booking(at10.add(Duration(days: page))),
                      booking(at10, doctor: 'Dr Other'),
                    ],
                    'pageInfo': {'hasMore': page < 2},
                  },
                },
              }),
              200,
            );
          }),
        );
        final bookings = await client.bookings(
          key: 'k',
          first: const CivilDate(2026, 10, 1),
          last: const CivilDate(2026, 10, 31),
          doctorName: 'merola',
        );
        expect(bookings, hasLength(2));
        expect(queries, hasLength(2));
        for (final query in queries) {
          expect(query, contains('start: "2026-10-01", end: "2026-11-01"'));
          for (final forbidden in [
            'patient',
            'comments',
            'reference',
            'cancellationReason',
            'mutation',
            'room',
          ]) {
            expect(query, isNot(contains(forbidden)));
          }
        }
        expect(queries.last, contains('page: 2'));
      },
    );
  });

  group('stima', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('con chiave e cognome la stima usa gli esiti Semble', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SembleSettings();
      await settings.save(key: 'k', userId: 'u1', doctorName: 'Merola');
      final service = PrivateEarningsService(
        _Agenda(db),
        semble: settings,
        client: SembleClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {
                  'bookings': {
                    'data': [booking(at10, dna: true)],
                    'pageInfo': {'hasMore': false},
                  },
                },
              }),
              200,
            ),
          ),
        ),
      );
      final result = await service.load(now: DateTime(2026, 10, 12, 18));
      expect(result.pence, 0);
      expect(result.dnaCounts, {PrivateFee.followUp30: 1});
      // The heydoc visit is not a Semble one and is left as it is.
      expect(result.scheduledPence, PrivateFee.followUp15.pence);
      expect(result.sembleVisits, 1);
      expect(result.sembleProblem, isNull);
    });

    test(
      'senza cognome o con Semble irraggiungibile resta la stima di oggi',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final settings = SembleSettings();
        await settings.save(key: 'k', userId: 'u1');
        var calls = 0;
        final service = PrivateEarningsService(
          _Agenda(db),
          semble: settings,
          client: SembleClient(
            client: MockClient((_) async {
              calls++;
              throw const SocketExceptionLike();
            }),
          ),
        );
        final now = DateTime(2026, 10, 12, 18);
        final unnamed = await service.load(now: now);
        expect(unnamed.pence, PrivateFee.followUp30.pence);
        expect(unnamed.sembleProblem, contains('cognome'));
        expect(calls, 0);

        await settings.save(key: null, userId: 'u1', doctorName: 'Merola');
        final offline = await service.load(now: now);
        expect(offline.pence, PrivateFee.followUp30.pence);
        expect(offline.sembleMatched, isNull);
        expect(offline.sembleProblem, contains('non raggiungibile'));
        expect(calls, 1);
      },
    );
  });

  group('calendario', () {
    const calendars = [
      AgendaCalendar(id: 'semble', name: 'Semble', accountName: ''),
      AgendaCalendar(id: 'kcl', name: 'KCL', accountName: ''),
    ];
    final at11 = at10.add(const Duration(hours: 1));
    List<AgendaEntry> adjust(
      List<SembleBooking> bookings,
      List<AgendaEntry> merged, {
      Set<String> hidden = const {},
    }) => sembleAdjustEntries(
      bookings: bookings,
      merged: merged,
      calendars: calendars,
      hiddenCalendarIds: hidden,
    );

    test('aggiunge solo le prenotazioni non ancora arrivate', () {
      final merged = [visit('Follow-up 30 · M.R.', at10)];
      final entries = adjust([
        parsed(booking(at10)),
        parsed(booking(at11, type: 'Prima visita')),
        parsed(booking(at11, type: 'Prima visita')),
        parsed(booking(at11.add(const Duration(hours: 1)), deleted: true)),
      ], merged);
      expect(entries, hasLength(2));
      expect(entries.first, same(merged.single));
      final added = entries.last;
      expect(added.isSembleBooking, isTrue);
      expect(added.title, 'Prima visita');
      expect(added.start, at11);
      expect(added.calendarIds, ['semble']);
      expect(added.isOrganizer, isFalse);
      // Any timed event in the same minute hides it.
      final kcl = AgendaEntry(
        instanceId: 'k',
        calendarIds: const ['kcl'],
        title: 'Meeting',
        start: at10,
        end: at11,
        allDay: false,
      );
      expect(adjust([parsed(booking(at10))], [kcl]), [kcl]);
      // Semble calendar hidden: nothing changes.
      expect(
        adjust([parsed(booking(at10))], const [], hidden: {'semble'}),
        isEmpty,
      );
    });

    test('la durata viene dal titolo, la pausa resta fuori', () {
      expect(sembleTitleMinutes('Follow-up Consultation (15 min)'), 15);
      expect(sembleTitleMinutes('Follow-up Consultation - 30 min (PLE)'), 30);
      expect(sembleTitleMinutes("Prima visita (adulto) 60'"), 60);
      expect(sembleTitleMinutes("Follow-up 30' · Insurance"), 30);
      expect(sembleTitleMinutes('Follow-up 30'), isNull);
      expect(sembleTitleMinutes('15 min o 30 min'), isNull);
      final ical = AgendaEntry(
        instanceId: 'ical',
        calendarIds: const ['semble'],
        title: "Prima visita (adulto) 60'",
        start: at10,
        end: at10.add(const Duration(minutes: 75)),
        allDay: false,
      );
      final kcl = AgendaEntry(
        instanceId: 'k',
        calendarIds: const ['kcl'],
        title: 'Meeting 15 min',
        start: at11,
        end: at11.add(const Duration(minutes: 60)),
        allDay: false,
      );
      final later = at10.add(const Duration(hours: 3));
      final entries = adjust(
        [
          parsed(booking(at10, minutes: 75)),
          parsed(
            booking(
              later,
              minutes: 30,
              type: 'Follow-up Consultation (15 min)',
            ),
          ),
        ],
        [ical, kcl],
      );
      expect(
        entries.map((e) => (e.instanceId, e.end.difference(e.start).inMinutes)),
        [
          ('ical', 60),
          ('k', 60),
          ('$sembleBookingPrefix${later.millisecondsSinceEpoch}', 15),
        ],
      );
    });

    test('in Italia le fasce di Londra si spostano di un ora', () {
      const bands = [
        SembleBand(SembleBandKind.available, 600, 1080),
        SembleBand(SembleBandKind.unavailable, 1380, 1440),
      ];
      expect(sembleShiftBands(bands, 60), const [
        SembleBand(SembleBandKind.available, 660, 1140),
      ]);
      expect(sembleShiftBands(bands, 0), same(bands));
      // Phone in London: no shift; elsewhere the difference from London.
      for (final day in const [
        CivilDate(2026, 10, 23),
        CivilDate(2026, 11, 10),
        CivilDate(2027, 3, 28),
      ]) {
        final noon = londonWallClock(
          DateTime.utc(day.year, day.month, day.day, 12),
        );
        expect(
          sembleZoneShift(day),
          noon.toLocal().timeZoneOffset.inMinutes -
              (londonSummerTime(noon) ? 60 : 0),
        );
      }
    });

    test('la pausa di 15 minuti non diventa spazio libero', () {
      const open = SembleBand(SembleBandKind.available, 600, 720);
      expect(sembleFreeBands([open], [(600, 615), (630, 645)]), const [
        SembleBand(SembleBandKind.available, 645, 720),
      ]);
      expect(sembleFreeBands([open], const []), [open]);
    });

    test('il calendario Semble non viene mai spostato', () {
      // 23 October 2026: Semble and its iCal copy agree on 10:00, 10:30…
      final day = DateTime(2026, 10, 23);
      DateTime h(int hour, [int minute = 0]) =>
          day.add(Duration(hours: hour, minutes: minute));
      final starts = [h(10), h(10, 30), h(11), h(12, 15), h(16), h(16, 30)];
      final bookings = [for (final start in starts) parsed(booking(start))];
      final ical = [
        for (final (index, start) in starts.indexed)
          visit('Visita $index', start, id: 'ical$index'),
      ];
      expect(adjust(bookings, ical), same(ical));
    });

    test('buildAgenda le mette nel giorno giusto, in ordine', () {
      final layer = SembleLayer()
        ..seedBookings([
          // Not one hour after the iCal visit, which in BST would be moved.
          parsed(
            booking(at10.add(const Duration(hours: 3)), type: 'Prima visita'),
          ),
        ]);
      final days = buildAgenda(
        events: [
          AgendaSourceEvent(
            instanceId: 'ical',
            calendarId: 'semble',
            title: 'Follow-up 30',
            start: at10,
            end: at10.add(const Duration(minutes: 30)),
            allDay: false,
          ),
        ],
        calendars: calendars,
        hiddenCalendarIds: const {},
        first: const CivilDate(2026, 10, 5),
        days: 1,
        adjust: layer.adjustEntries(calendars, const {}),
      );
      expect(days.single.entries.map((e) => e.title), [
        'Follow-up 30',
        'Prima visita',
      ]);
      expect(SembleLayer().adjustEntries(calendars, const {}), isNull);
    });
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

class _Agenda extends AgendaService {
  _Agenda(super.database);

  @override
  Future<AgendaAccess> access() async => AgendaAccess.granted;

  @override
  Future<List<AgendaCalendar>> calendars() async => const [
    AgendaCalendar(id: 'semble', name: 'Semble', accountName: ''),
    AgendaCalendar(id: 'heydoc', name: 'heydoc', accountName: ''),
  ];

  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime start,
    DateTime end,
    List<String> calendarIds,
  ) async => [
    AgendaSourceEvent(
      instanceId: 'semble-visit',
      calendarId: 'semble',
      title: 'Follow-up 30',
      start: at10,
      end: at10.add(const Duration(minutes: 30)),
      allDay: false,
    ),
    AgendaSourceEvent(
      instanceId: 'heydoc-visit',
      calendarId: 'heydoc',
      title: 'Follow-up',
      start: DateTime(2026, 10, 20, 10),
      end: DateTime(2026, 10, 20, 10, 15),
      allDay: false,
    ),
  ];
}
