import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class DeviceTimeZoneService {
  DeviceTimeZoneService._();

  static bool _databaseInitialized = false;

  static Future<String> currentIana() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      return 'UTC';
    }
  }

  static Future<tz.Location> location([String? preferred]) async {
    if (!_databaseInitialized) {
      tz_data.initializeTimeZones();
      _databaseInitialized = true;
    }
    final identifier = preferred ?? await currentIana();
    try {
      return tz.getLocation(identifier);
    } on ArgumentError {
      return tz.UTC;
    }
  }
}
