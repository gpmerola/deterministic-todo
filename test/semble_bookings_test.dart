import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/private_earnings.dart';
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

// Synthetic bookings shaped like Semble's (ISO in UTC); no real data.
Map<String, Object?> booking(
  DateTime start, {
  int minutes = 30,
  bool deleted = false,
  String doctor = 'Dr Test Merola',
  String type = 'Follow-up 30',
  bool arrived = false,
  bool dna = false,
}) => {
  'start': start.toUtc().toIso8601String(),
  'end': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
  'deleted': deleted,
  'doctorName': doctor,
  'appointment': {'title': type},
  'bookingJourney': {
    'arrived': arrived ? start.toUtc().toIso8601String() : null,
    'consultation': null,
    'departed': null,
    'dna': dna ? start.toUtc().toIso8601String() : null,
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

    test('orari senza Z sono UTC, non ora del telefono', () {
      final utc = DateTime.utc(2026, 10, 23, 15, 30);
      for (final text in [
        '2026-10-23T15:30:00.000',
        '2026-10-23 15:30:00',
        '2026-10-23T15:30:00.000Z',
        '2026-10-23T16:30:00+01:00',
      ]) {
        expect(
          SembleBooking.fromJson({'start': text})!.start,
          utc.toLocal(),
          reason: text,
        );
      }
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
        // The iCal copy one hour early in a calendar named otherwise.
        entry('opuk', 'opuk', 'Prima visita 60 min', h(16, 30)),
        entry('heydoc', 'heydoc', 'Follow-up 15 min', h(14)),
      ],
      bookings: bookings,
      sembleCalendarIds: const {'semble'},
      now: now,
      offsetOf: (_) => const Duration(hours: 1),
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
    Duration utc(DateTime _) => Duration.zero;
    Duration bst(DateTime _) => const Duration(hours: 1);
    List<AgendaEntry> adjust(
      List<SembleBooking> bookings,
      List<AgendaEntry> merged, {
      Set<String> hidden = const {},
      Duration Function(DateTime)? offsetOf,
    }) => sembleAdjustEntries(
      bookings: bookings,
      merged: merged,
      calendars: calendars,
      hiddenCalendarIds: hidden,
      offsetOf: offsetOf ?? utc,
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

    test('la copia iCal scritta in UTC torna all ora giusta', () {
      // Booking 17:30 local in BST; the iCal copy shows 16:30.
      final early = visit('Prima visita · M.R.', at10, id: 'ical');
      final entries = adjust(
        [parsed(booking(at11, minutes: 75, type: 'Initial Consultation'))],
        [early],
        offsetOf: bst,
      );
      final moved = entries.single;
      expect(moved.instanceId, 'ical');
      expect(moved.title, 'Prima visita · M.R.');
      expect(moved.start, at11);
      expect(moved.end, at11.add(const Duration(minutes: 30)));
      // Without the offset, or with a booking at its own time, it stays.
      expect(
        adjust([parsed(booking(at11))], [early]).map((e) => e.instanceId),
        ['ical', '$sembleBookingPrefix${at11.millisecondsSinceEpoch}'],
      );
      expect(
        adjust(
          [parsed(booking(at10)), parsed(booking(at11))],
          [early],
          offsetOf: bst,
        ).first.start,
        at10,
      );
      // A KCL meeting is never moved.
      final kcl = AgendaEntry(
        instanceId: 'k',
        calendarIds: const ['kcl'],
        title: 'Meeting',
        start: at10,
        end: at11,
        allDay: false,
      );
      expect(
        adjust([parsed(booking(at11))], [kcl], offsetOf: bst).first,
        same(kcl),
      );
    });

    test('visite vicine: la giornata si sposta tutta insieme', () {
      // 23 October 2026 as read from Semble (local BST) and the iCal copies
      // in UTC digits: several early copies land on another booking.
      final day = DateTime(2026, 10, 23);
      DateTime h(int hour, [int minute = 0]) =>
          day.add(Duration(hours: hour, minutes: minute));
      final bookings = [
        for (final (start, minutes) in [
          (h(11), 30),
          (h(11, 30), 30),
          (h(12), 45),
          (h(13, 15), 45),
          (h(17), 30),
          (h(17, 30), 75),
        ])
          parsed(booking(start, minutes: minutes)),
      ];
      final ical = [
        for (final (index, start) in [
          h(10),
          h(10, 30),
          h(11),
          h(12, 15),
          h(16),
          h(16, 30),
        ].indexed)
          visit('Visita $index', start, id: 'ical$index'),
      ];
      final entries = adjust(bookings, ical, offsetOf: bst);
      expect(entries.map((e) => e.instanceId), [
        for (var index = 0; index < 6; index++) 'ical$index',
      ]);
      expect(entries.map((e) => e.start), bookings.map((b) => b.start));
      // A day whose copies are at the right time is left alone.
      final right = [
        for (final (index, booking) in bookings.indexed)
          visit('Visita $index', booking.start, id: 'ok$index'),
      ];
      expect(adjust(bookings, right, offsetOf: bst), right);
    });

    test('l esito si abbina anche alla copia un ora prima', () {
      expect(
        sembleOutcomeFor(visit('Follow-up', at10), [
          parsed(booking(at11, dna: true)),
        ], offsetOf: bst),
        SembleOutcome.dna,
      );
      expect(
        sembleOutcomeFor(visit('Follow-up', at10), [
          parsed(booking(at11, dna: true)),
        ], offsetOf: utc),
        SembleOutcome.unknown,
      );
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
