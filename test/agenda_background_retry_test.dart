import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/services/agenda_mirror.dart';
import 'package:deterministic_todo/services/agenda_phone_sync.dart';
import 'package:deterministic_todo/services/agenda_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/sync_server.dart';

/// Holds the first calendar-access check until [release] completes.
class _GatedService extends AgendaService {
  _GatedService(super.database);
  final release = Completer<void>();
  int accessChecks = 0;

  @override
  Future<AgendaAccess> access() async {
    accessChecks++;
    if (accessChecks == 1) await release.future;
    return AgendaAccess.noMirror;
  }
}

void main() {
  test('failure codes keep only the class and a short Supabase code', () {
    expect(
      agendaFailureCode(
        const PostgrestException(message: 'Riunione', code: '42501'),
      ),
      'error_supabase_42501',
    );
    expect(
      agendaFailureCode(
        const PostgrestException(message: 'x', code: 'a b; drop'),
      ),
      'error_supabase',
    );
    expect(agendaFailureCode(TimeoutException('t')), 'error_timeout');
    expect(
      agendaFailureCode(StateError('Riunione con Mario')),
      'error_unexpected',
    );
  });

  test(
    'a second upload waits for the running one instead of failing',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final server = SyntheticSyncServer();
      final client = await server.client();
      addTearDown(client.dispose);
      final service = _GatedService(db);
      final mirror = AgendaMirror(
        service: service,
        client: client,
        deviceId: 'd',
      );

      final first = mirror.upload();
      final second = mirror.upload();
      await pumpEventQueue();
      // The second call is queued, not answered "busy".
      expect(service.accessChecks, 1);
      service.release.complete();

      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(service.accessChecks, 2);
      expect(mirror.lastFailure, 'no_access');
    },
  );

  test('background runs report why they need a retry', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final server = SyntheticSyncServer();
    final client = await server.client();
    addTearDown(client.dispose);
    final service = _GrantedService(db);
    final sync = AgendaPhoneSync(
      service: service,
      client: client,
      deviceId: 'd',
    );

    final result = await sync.background('calendar');

    expect(result, startsWith('retry:'));
    expect(result, matches(RegExp(r'^retry:[A-Za-z0-9_]+$')));
  });
}

class _GrantedService extends AgendaService {
  _GrantedService(super.database);

  @override
  Future<AgendaAccess> access() async => AgendaAccess.granted;
}
