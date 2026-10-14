import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_mirror.dart';
import 'package:deterministic_todo/services/agenda_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Invitations shown only once accepted (build 274): "Peer Review &
// Safeguarding concerns" appears in the Calendar only when accepted.

const google = AgendaCalendar(
  id: 'google',
  name: 'Calendar',
  accountName: 'gmail',
);
const exchange = AgendaCalendar(
  id: 'exchange',
  name: 'Calendar',
  accountName: 'kcl',
);
const peerReview = 'Peer Review & Safeguarding concerns';

/// A row as the Android channel sends it.
AgendaSourceEvent _row(
  String title, {
  String calendar = 'google',
  String id = 'e1',
  bool unanswered = false,
  bool answered = false,
  bool accepted = false,
}) => agendaEventFromRow({
  'instanceId': id,
  'calendarId': calendar,
  'title': title,
  'start': DateTime(2026, 10, 15, 13).millisecondsSinceEpoch,
  'end': DateTime(2026, 10, 15, 14).millisecondsSinceEpoch,
  'allDay': false,
  'unanswered': unanswered,
  'answered': answered,
  'accepted': accepted,
});

List<String> _titles(List<AgendaSourceEvent> events) => [
  for (final entry in mergeAgendaEntries(
    events: events,
    calendars: const [google, exchange],
    hiddenCalendarIds: const {},
  ))
    entry.title,
];

void main() {
  test('accettato: visibile', () {
    expect(_titles([_row(peerReview, answered: true, accepted: true)]), [
      peerReview,
    ]);
  });

  test('in attesa, forse, rifiutato o sconosciuto: nascosto', () {
    expect(_titles([_row(peerReview, unanswered: true)]), isEmpty);
    // Tentative and declined are answered but not accepted.
    expect(_titles([_row(peerReview, answered: true)]), isEmpty);
    expect(_titles([_row(peerReview)]), isEmpty);
  });

  test('maiuscole e spazi superflui non contano', () {
    expect(
      _titles([_row('  peer review   &  SAFEGUARDING concerns ')]),
      isEmpty,
    );
  });

  test('altri titoli invariati, anche non accettati', () {
    expect(_titles([_row('TNG Meeting', unanswered: true)]), ['TNG Meeting']);
    expect(_titles([_row('Peer Review')]), ['Peer Review']);
  });

  test('basta la copia Google accettata se Exchange non sa la risposta', () {
    expect(
      _titles([
        _row(peerReview, calendar: 'exchange', id: 'x1'),
        _row(peerReview, id: 'g1', answered: true, accepted: true),
      ]),
      [peerReview],
    );
  });

  test('copia Web: contiene solo ciò che il telefono mostra', () {
    final days = buildAgenda(
      events: [
        _row(peerReview, unanswered: true),
        _row('TNG Meeting', id: 'e2'),
      ],
      calendars: const [google],
      hiddenCalendarIds: const {},
      first: const CivilDate(2026, 10, 15),
      days: 1,
    );
    final mirror = buildAgendaMirror(
      days: days,
      calendars: const [google],
      first: const CivilDate(2026, 10, 15),
      count: 1,
      deviceId: 'device',
      zoneLabel: null,
      taskLinks: const {},
    );
    final events = mirror['events']! as List<Map<String, Object?>>;
    expect([for (final event in events) event['title']], ['TNG Meeting']);

    // An accepted one that reached the mirror stays visible on the web.
    final web = WebAgendaService.fromRow({
      'instance_key': 'e1',
      'calendar_keys': ['google'],
      'title': peerReview,
      'starts_at': '2026-10-15T12:00:00Z',
      'ends_at': '2026-10-15T13:00:00Z',
      'all_day': false,
    });
    expect(_titles([web]), [peerReview]);
  });
}
