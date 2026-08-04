import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/services/calendar_service.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCalendar extends Mock implements DeviceCalendar {}

void main() {
  late AppDatabase database;
  late TaskRepository repository;
  late _MockCalendar calendar;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(database, deviceId: 'device-test');
    calendar = _MockCalendar();
  });

  tearDown(() => database.close());

  test('richiede esplicitamente una data prima dell’esportazione', () async {
    final id = await repository.create('Senza data');
    final task = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals(id))).getSingle();

    expect(
      () => CalendarService(
        database,
        calendar: calendar,
        isAndroid: true,
      ).exportTask(task),
      throwsFormatException,
    );
  });

  test(
    'preferisce Google e aggiorna lo stesso evento senza duplicarlo',
    () async {
      final id = await repository.create('Evento deterministico');
      var task = await (database.select(
        database.tasks,
      )..where((row) => row.id.equals(id))).getSingle();
      await repository.updateDetails(
        task,
        title: task.title,
        dueDate: '2026-08-04',
      );
      task = await (database.select(
        database.tasks,
      )..where((row) => row.id.equals(id))).getSingle();
      when(
        () => calendar.requestPermissions(),
      ).thenAnswer((_) async => CalendarPermissionStatus.granted);
      when(() => calendar.listCalendars()).thenAnswer(
        (_) async => const [
          Calendar(id: 'local', name: 'Samsung', readOnly: false),
          Calendar(
            id: 'google',
            name: 'Google',
            readOnly: false,
            accountType: 'com.google',
            isPrimary: true,
          ),
        ],
      );
      when(
        () => calendar.createEvent(
          calendarId: any(named: 'calendarId'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          timeZone: any(named: 'timeZone'),
        ),
      ).thenAnswer((_) async => 'event-1');
      when(
        () => calendar.updateEvent(
          eventId: any(named: 'eventId'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          description: any(named: 'description'),
          isAllDay: any(named: 'isAllDay'),
          timeZone: any(named: 'timeZone'),
        ),
      ).thenAnswer((_) async {});
      final service = CalendarService(
        database,
        calendar: calendar,
        isAndroid: true,
      );

      expect((await service.exportTask(task)).calendarName, 'Google');
      await service.exportTask(task);

      verify(
        () => calendar.createEvent(
          calendarId: 'google',
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          timeZone: any(named: 'timeZone'),
        ),
      ).called(1);
      verify(
        () => calendar.updateEvent(
          eventId: 'event-1',
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          description: any(named: 'description'),
          isAllDay: any(named: 'isAllDay'),
          timeZone: any(named: 'timeZone'),
        ),
      ).called(1);
    },
  );
}
