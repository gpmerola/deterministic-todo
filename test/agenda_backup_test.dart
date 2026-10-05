import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_backup.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Supabase backup of Todo's own Agenda data (build 227). Synthetic data.

const kcl = AgendaCalendar(id: '7', name: 'Calendar', accountName: 'kcl');
const todo = AgendaCalendar(
  id: '12',
  name: AgendaService.localCalendarName,
  accountName: AgendaService.localAccountName,
  colorHex: '#616161',
  writable: true,
  localOnly: true,
);

Map<String, Object?> _backup({
  List<Map<Object?, Object?>> events = const [],
  Map<String, bool> choices = const {},
}) => buildAgendaBackup(
  calendars: const [kcl, todo],
  localEvents: events,
  filter: AgendaFilter(
    hiddenEvents: [
      HiddenAgendaEvent(
        key: 'ward|1|2|false',
        title: 'Ward round',
        start: DateTime.utc(2026, 10, 6, 8),
        allDay: false,
      ),
    ],
  ),
  choices: choices,
  colors: const {'7': '#039BE5', 'gone': '#000000'},
  mainCalendarId: '12',
  aiCalendarId: null,
  viewMode: AgendaViewMode.month,
  taskLinks: const {'task:b', 'task:a'},
);

void main() {
  test('the hash ignores the order of native map keys', () {
    final a = _backup(
      events: [
        {'id': 1, 'title': 'MDT', 'dtstart': 10, 'rrule': 'FREQ=WEEKLY'},
      ],
    );
    final b = _backup(
      events: [
        {'rrule': 'FREQ=WEEKLY', 'dtstart': 10, 'title': 'MDT', 'id': 1},
      ],
    );
    expect(agendaBackupHash(a), agendaBackupHash(b));
    expect(
      agendaBackupHash(a),
      isNot(agendaBackupHash(_backup(choices: const {'7': false}))),
    );
  });

  test('calendars are named by account and name, never by phone id', () {
    final settings =
        _backup(choices: const {'7': false, '12': true})['settings']! as Map;
    expect(settings['choices'], {
      'kcl\u001fCalendar': false,
      'Todo\u001fTodo (solo telefono)': true,
    });
    // A colour of a calendar no longer on the phone is dropped.
    expect(settings['colors'], {'kcl\u001fCalendar': '#039BE5'});
    expect(settings['main'], 'Todo\u001fTodo (solo telefono)');
    expect(settings['ai'], isNull);
    expect(settings['task_links'], ['task:a', 'task:b']);
  });

  test('hidden events round-trip through the stored filter', () {
    final settings = _backup()['settings']! as Map;
    final filter = AgendaService.filterFromJson(settings['filter']! as Map);
    expect(filter.hiddenEvents.single.key, 'ward|1|2|false');
    expect(filter.hideHolidays, isTrue);
    final remote = RemoteAgendaBackup(
      hash: 'h',
      savedAt: DateTime(2026, 10, 5),
      payload: _backup(events: const [{}, {}]),
    );
    expect(remote.eventCount, 2);
    expect(remote.hiddenCount, 1);
  });
}
