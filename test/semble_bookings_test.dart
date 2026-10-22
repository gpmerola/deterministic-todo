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
      expect(result.sembleMatched, (matched: 1, checked: 1));
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

    test('solo le prenotazioni non ancora arrivate dal calendario', () {
      final merged = [visit('Follow-up 30 · M.R.', at10)];
      final entries = sembleDirectEntries(
        bookings: [
          parsed(booking(at10)),
          parsed(booking(at11, type: 'Prima visita')),
          parsed(booking(at11, type: 'Prima visita')),
          parsed(booking(at11.add(const Duration(hours: 1)), deleted: true)),
        ],
        merged: merged,
        calendars: calendars,
        hiddenCalendarIds: const {},
      );
      expect(entries, hasLength(1));
      final added = entries.single;
      expect(added.isSembleBooking, isTrue);
      expect(added.title, 'Prima visita');
      expect(added.start, at11);
      expect(added.calendarIds, ['semble']);
      expect(added.isOrganizer, isFalse);
      // The iCal copy in a calendar with another name hides it too.
      expect(
        sembleDirectEntries(
          bookings: [parsed(booking(at10))],
          merged: [
            AgendaEntry(
              instanceId: 'k',
              calendarIds: const ['kcl'],
              title: 'Meeting',
              start: at10,
              end: at11,
              allDay: false,
            ),
          ],
          calendars: calendars,
          hiddenCalendarIds: const {},
        ),
        isEmpty,
      );
      // Semble calendar hidden or missing: nothing is added.
      expect(
        sembleDirectEntries(
          bookings: [parsed(booking(at10))],
          merged: const [],
          calendars: calendars,
          hiddenCalendarIds: const {'semble'},
        ),
        isEmpty,
      );
    });

    test('buildAgenda le mette nel giorno giusto, in ordine', () {
      final layer = SembleLayer()
        ..seedBookings([parsed(booking(at11, type: 'Prima visita'))]);
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
        extra: layer.directEntries(calendars, const {}),
      );
      expect(days.single.entries.map((e) => e.title), [
        'Follow-up 30',
        'Prima visita',
      ]);
      expect(SembleLayer().directEntries(calendars, const {}), isNull);
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
