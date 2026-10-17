import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/task.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:deterministic_todo/ui/views/agenda_load_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service extends AgendaService {
  _Service(super.db);
  int calls = 0;
  Completer<void>? gate;
  AgendaAccess permission = AgendaAccess.granted;
  @override
  Future<AgendaAccess> access() async {
    calls++;
    await gate?.future;
    return permission;
  }

  @override
  Future<String?> deviceZoneLabel() async => 'Europe/London';
  @override
  Future<AgendaViewMode> viewMode() async => AgendaViewMode.list;
  @override
  Future<AgendaFilter> filter() async => AgendaFilter.none;
  @override
  Future<List<AgendaCalendar>> calendars() async => const [];
  @override
  Future<Map<String, bool>> calendarChoices() async => const {};
  @override
  Future<List<AgendaSourceEvent>> events(
    DateTime a,
    DateTime b,
    List<String> ids,
  ) async => [];
  @override
  Future<List<AgendaTaskItem>> tasks(CivilDate first, int days) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.deterministic.todo/agenda');
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });

  test(
    'equivalent loads coalesce; a concurrent edit guarantees a later read',
    () async {
      final service = _Service(db)..gate = Completer<void>();
      final controller = AgendaLoadController(service);
      final day = CivilDate(2026, 10, 12);
      final first = controller.load(day, 14);
      final duplicate = controller.load(day, 14);
      expect(identical(first, duplicate), isTrue);
      expect(service.calls, 1);
      final edited = controller.load(day, 14, changed: true);
      service.gate!.complete();
      final result = await edited;
      expect(service.calls, 2);
      expect(result.days, hasLength(14));
      expect(identical(await first, result), isTrue);
      service.permission = AgendaAccess.denied;
      expect((await controller.load(day, 14)).access, AgendaAccess.denied);
      controller.dispose();
    },
  );

  test(
    'unchanged provider reuses range, changed or unavailable revision rereads',
    () async {
      String? token = 'process:1';
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'revision') return token;
            if (call.method == 'instances') {
              reads++;
              return <Object>[];
            }
            return null;
          });
      final service = AgendaService(db);
      final start = DateTime(2026, 10, 1), end = DateTime(2026, 11, 1);
      for (var i = 0; i < 10; i++) {
        await service.events(start, end, ['synthetic']);
      }
      expect(reads, 1);
      token = 'process:2';
      await service.events(start, end, ['synthetic']);
      expect(reads, 2);
      token = null;
      await service.events(start, end, ['synthetic']);
      await service.events(start, end, ['synthetic']);
      expect(reads, 4);
    },
  );

  test(
    'TTL and explicit refresh bypass a matching provider revision',
    () async {
      var now = DateTime(2026, 10, 12);
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'revision') return 'stable';
            if (call.method == 'instances') {
              reads++;
              return <Object>[];
            }
            return null;
          });
      final service = AgendaService(db, now: () => now);
      final start = DateTime(2026, 10, 1), end = DateTime(2026, 11, 1);
      await service.events(start, end, ['synthetic']);
      now = now.add(AgendaService.eventCacheLifetime);
      await service.events(start, end, ['synthetic']);
      expect(reads, 2);
      service.invalidateEventCache();
      await service.events(start, end, ['synthetic']);
      expect(reads, 3);
    },
  );

  test(
    'concurrent ranges share a read and a change during it invalidates the cache',
    () async {
      var token = 'process:1';
      var reads = 0;
      final gate = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'revision') return token;
            if (call.method == 'instances') {
              reads++;
              await gate.future;
              return <Object>[];
            }
            return null;
          });
      final service = AgendaService(db);
      final start = DateTime(2026, 10, 1), end = DateTime(2026, 11, 1);
      final requests = [
        service.events(start, end, ['synthetic']),
        service.events(start, end, ['synthetic']),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      token = 'process:2';
      gate.complete();
      await Future.wait(requests);
      await service.events(start, end, ['synthetic']);
      expect(reads, 2);
    },
  );
}
