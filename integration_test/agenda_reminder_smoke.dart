// Synthetic-only harness; run with tools/agenda_provider_smoke.py --reminders.
import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/services/agenda_phone_sync.dart';
import 'package:deterministic_todo/services/agenda_reminders.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final service = AgendaService(db);
  final reminders = AgendaReminders(service);
  final cleanup = <String>[];
  var phase = 'permission';
  var status = 'FAIL';
  // Keep the provider-triggered jobs in this isolated in-memory test engine.
  AgendaPhoneSync.backgroundChannel.setMethodCallHandler((_) async => 'done');
  try {
    if (await service.access() != AgendaAccess.granted) {
      throw StateError('Calendar permission');
    }
    final permissions = await reminders.status();
    if (permissions['notifications'] != true || permissions['exact'] != true) {
      throw StateError('Notification permissions');
    }
    final calendar = (await service.localCalendar())!;
    await service.saveCalendarChoices({
      for (final item in await service.calendars())
        item.id: item.id == calendar.id,
    });
    Future<String> create() async {
      final start = DateTime.now().add(const Duration(minutes: 30, seconds: 4));
      final id = await service.createEvent(
        AgendaEventDraft(
          calendarId: calendar.id,
          title: 'QA245 reminder synthetic',
          start: start,
          end: start.add(const Duration(hours: 1)),
        ),
      );
      cleanup.add(id);
      return id;
    }

    Future<void> waitDelivery() =>
        Future<void>.delayed(const Duration(seconds: 7));
    phase = 'delivery';
    await create();
    await reminders.refresh();
    phase = 'scheduled_count';
    if ((await reminders.status())['scheduled'] != 1) {
      throw StateError('Missing alarm');
    }
    phase = 'stale_plan';
    final oldGeneration = await AgendaReminders.channel.invokeMethod<int>(
      'beginReminders',
    );
    await AgendaReminders.channel.invokeMethod<int>('beginReminders');
    await AgendaReminders.channel.invokeMethod<void>('replaceReminders', {
      'generation': oldGeneration,
      'enabled': false,
      'accessible': true,
      'events': <Object>[],
    });
    if ((await reminders.status())['scheduled'] != 1) {
      throw StateError('Stale background plan replaced the newer state');
    }
    await waitDelivery();
    phase = 'delivered_count';
    if ((await reminders.status())['posted'] != 1) {
      throw StateError('Missing notification');
    }
    await reminders.refresh();
    if ((await reminders.status())['scheduled'] != 0) {
      throw StateError('Duplicate schedule');
    }
    phase = 'disable';
    await reminders.setEnabled(false);
    if ((await reminders.status())['posted'] != 0) {
      throw StateError('Notification not cleared');
    }
    // Delete before the trigger without refreshing Dart: native validation
    // must suppress the stale cached reminder by consulting Instances.
    phase = 'deleted_event';
    final deleted = await create();
    await reminders.setEnabled(true);
    await service.deleteEvent(deleted);
    cleanup.remove(deleted);
    await waitDelivery();
    if ((await reminders.status())['posted'] != 0) {
      throw StateError('Deleted event notified');
    }
    phase = 'moved_event';
    final moved = await create();
    await reminders.refresh();
    final later = DateTime.now().add(const Duration(hours: 2));
    await service.updateEvent(
      moved,
      AgendaEventDraft(
        calendarId: calendar.id,
        title: 'QA245 moved synthetic',
        start: later,
        end: later.add(const Duration(hours: 1)),
      ),
    );
    await waitDelivery();
    if ((await reminders.status())['posted'] != 0) {
      throw StateError('Moved event notified at old time');
    }
    phase = 'disabled_alarm';
    await create();
    await reminders.refresh();
    await reminders.setEnabled(false);
    await waitDelivery();
    final disabled = await reminders.status();
    if (disabled['posted'] != 0 || disabled['scheduled'] != 0) {
      throw StateError('Disabled alarm fired');
    }
    status = 'PASS';
  } catch (_) {
    status = 'FAIL ($phase)';
  } finally {
    await reminders.setEnabled(false);
    for (final id in cleanup) {
      await service.deleteEvent(id);
    }
    await db.close();
  }
  // Fixed status only, no personal or event data.
  debugPrint('AGENDA_PROVIDER_SMOKE: $status');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    ),
  );
}
