import 'memory_snapshot.dart';

const bool isWebPlatform = true;
bool get isAndroidPlatform => false;
String get operatingSystemName => 'web';
int get currentRssBytes => 0;
Future<MemorySnapshot?> readMemorySnapshot() async => null;
Future<int> databaseSizeBytes() async => 0;
