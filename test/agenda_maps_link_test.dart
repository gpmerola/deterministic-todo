import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/ui/views/agenda_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

AgendaEntry _event(String? location) => AgendaEntry(
  instanceId: 'e',
  calendarIds: const ['c'],
  title: 'Visita',
  start: DateTime(2026, 10, 16, 9),
  end: DateTime(2026, 10, 16, 10),
  allDay: false,
  location: location,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('an address becomes a Google Maps search', () {
    final uri = agendaMapsUri('  Denmark Hill,\n London SE5 8AZ ');
    expect(uri?.host, 'www.google.com');
    expect(uri?.path, '/maps/search/');
    expect(uri?.queryParameters, {
      'api': '1',
      'query': 'Denmark Hill, London SE5 8AZ',
    });
  });

  test('blank text, links and online meetings have no map', () {
    for (final location in [
      null,
      '',
      '   ',
      'https://teams.microsoft.com/l/meetup-join/x',
      'www.example.com',
      'Microsoft Teams Meeting',
      'Riunione di Microsoft Teams',
      'Zoom',
      'Google Meet',
    ]) {
      expect(agendaMapsUri(location), isNull, reason: '$location');
    }
    // A place that only mentions Teams is still a place.
    expect(agendaMapsUri('Sala Teams, Maudsley'), isNotNull);
  });

  Future<void> pumpSheet(WidgetTester tester, String location) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaEventSheet(
              entry: _event(location),
              calendarName: 'KCL',
              editable: false,
              zoneLabel: 'Europe/London',
            ),
          ),
        ),
      );

  testWidgets('the sheet makes an address tappable', (tester) async {
    await pumpSheet(tester, 'Maudsley Hospital');
    expect(find.byKey(const ValueKey('agenda-sheet-location')), findsOneWidget);
    expect(find.text('Maudsley Hospital'), findsOneWidget);
  });

  testWidgets('an online meeting place stays plain text', (tester) async {
    await pumpSheet(tester, 'Microsoft Teams Meeting');
    expect(find.byKey(const ValueKey('agenda-sheet-location')), findsNothing);
    expect(find.text('Microsoft Teams Meeting'), findsOneWidget);
  });
}
