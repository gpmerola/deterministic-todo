import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/local/database.dart';
import 'device_time_zone_service.dart';

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _permissionsRequested = false;

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      macOS: DarwinInitializationSettings(),
      windows: WindowsInitializationSettings(
        appName: 'Attività',
        appUserModelId: 'app.deterministic.todo',
        guid: '5af1ea33-72ce-4cc4-96f5-fb983635f69b',
      ),
    );
    await _plugin.initialize(settings);
  }

  Future<void> _ensurePermissions() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }

  Future<void> schedule(Task task) async {
    await cancel(task.id);
    if (task.timeMinutes == null ||
        task.showDate == null ||
        task.deletedAt != null ||
        task.completedAt != null) {
      return;
    }
    await _ensurePermissions();
    final location = await DeviceTimeZoneService.location(task.timeZone);
    final date = task.showDate!.split('-').map(int.parse).toList();
    final hour = task.timeMinutes! ~/ 60;
    final minute = task.timeMinutes! % 60;
    final when = tz.TZDateTime(
      location,
      date[0],
      date[1],
      date[2],
      hour,
      minute,
    );
    if (when.isBefore(tz.TZDateTime.now(location))) return;
    await _plugin.zonedSchedule(
      task.id.hashCode & 0x7fffffff,
      'Attività',
      task.title,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('tasks', 'Attività con orario'),
        macOS: DarwinNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: task.id,
    );
  }

  Future<void> cancel(String taskId) =>
      _plugin.cancel(taskId.hashCode & 0x7fffffff);
}
