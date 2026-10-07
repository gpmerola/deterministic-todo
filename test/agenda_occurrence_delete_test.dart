import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Calendar extends Mock implements DeviceCalendar {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.deterministic.todo/agenda');
  late AppDatabase db;
  late _Calendar calendar;
  late AgendaService service;
  late List<MethodCall> native;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendar = _Calendar();
    service = AgendaService(db, calendar: calendar);
    native = [];
    when(
      () => calendar.deleteEvent(instanceId: any(named: 'instanceId')),
    ).thenAnswer((_) async {});
    when(
      () => calendar.deleteRecurring(any(), EventSpan.allEvents),
    ).thenAnswer((_) async {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          native.add(call);
          final id = (call.arguments as Map)['eventId'];
          return switch (call.method) {
            // Row 77 replaced the occurrence of series 5 at 1000.
            'seriesOccurrence' => id == '77' ? '5@1000' : null,
            'cancelOccurrence' => id == '77' ? 1 : 0,
            _ => null,
          };
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });

  test('una occorrenza modificata viene annullata, non ripristinata', () async {
    await service.deleteEvent('77');

    expect(native.map((c) => c.method), [
      'seriesOccurrence',
      'cancelOccurrence',
    ]);
    verifyNever(
      () => calendar.deleteEvent(instanceId: any(named: 'instanceId')),
    );
  });

  test('tutta la serie da una occorrenza modificata usa la serie', () async {
    await service.deleteEvent('77', series: true);

    verify(() => calendar.deleteRecurring('5@1000', EventSpan.allEvents));
  });

  test('evento singolo e occorrenza normale passano al plugin', () async {
    await service.deleteEvent('12');
    await service.deleteEvent('5@2000');

    verify(() => calendar.deleteEvent(instanceId: '12'));
    verify(() => calendar.deleteEvent(instanceId: '5@2000'));
    // An id with "@" is already a series slot: no native lookup.
    expect(native.where((c) => c.method == 'seriesOccurrence'), hasLength(1));
  });

  test('una occorrenza modificata resta parte della serie', () {
    Map<Object?, Object?> row(String id, {bool changed = false}) => {
      'instanceId': id,
      'calendarId': 'cal',
      'title': 'Visita',
      'start': DateTime(2026, 10, 17, 7).millisecondsSinceEpoch,
      'end': DateTime(2026, 10, 17, 8).millisecondsSinceEpoch,
      if (changed) 'changedOccurrence': true,
    };
    const calendar = AgendaCalendar(
      id: 'cal',
      name: 'Personale',
      accountName: 'me@example.com',
      writable: true,
    );
    List<AgendaEntry> merged(Map<Object?, Object?> source) =>
        mergeAgendaEntries(
          events: [agendaEventFromRow(source)],
          calendars: const [calendar],
          hiddenCalendarIds: const {},
        );

    // Exception rows carry a bare id: before this, Todo treated them as
    // one-off events and offered no "Tutta la serie".
    expect(merged(row('77', changed: true)).single.recurring, isTrue);
    expect(merged(row('12')).single.recurring, isFalse);
    expect(merged(row('5@2000')).single.recurring, isTrue);
  });
}
