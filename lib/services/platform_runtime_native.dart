import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const bool isWebPlatform = false;
bool get isAndroidPlatform => Platform.isAndroid;
String get operatingSystemName => Platform.operatingSystem;
int get currentRssBytes => ProcessInfo.currentRss;

Future<int> databaseSizeBytes() async {
  final support = await getApplicationSupportDirectory();
  final database = File(p.join(support.path, 'deterministic_todo.sqlite'));
  return await database.exists() ? database.length() : 0;
}
