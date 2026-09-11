import 'dart:convert';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/sync/task_sync_writer.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/task.dart' as domain;
import 'package:deterministic_todo/domain/task_planning.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Fixture {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final repo = TaskRepository(db, deviceId: 'phone');
  late SupabaseClient client;
  late Task original;
  Map<String, dynamic>? remote;
  Future<void> Function()? beforeWrite;
  Future<void> Function()? afterWrite;
  Future<void> Function()? beforePull;
  int writes = 0;
  int receipts = 0;
  bool loseResponse = false;

  Future<void> init() async {
    await repo.create(
      'Originale sintetico',
      status: domain.TaskStatus.scheduled,
      showDate: '2026-09-07',
      notes: 'Nota iniziale',
    );
    original = await db.select(db.tasks).getSingle();
    await db.delete(db.outboxEntries).go();
    remote = taskToRemote(original, 'user');
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response reply(Object? data, {int status = 200}) => http.Response(
          jsonEncode(data),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/todo_task_fingerprints_v1') ||
            request.url.path.endsWith('/todo_sync_overview_v1')) {
          return reply({
            'code': 'PGRST202',
            'message': 'RPC missing',
          }, status: 404);
        }
        if (request.url.path.endsWith('/tasks')) {
          if (request.method == 'GET') {
            if (!request.url.queryParameters.containsKey('id')) {
              await beforePull?.call();
            }
            final cursor = request.url.queryParameters['id'];
            return reply(
              remote == null ||
                      (cursor?.startsWith('gt.') == true &&
                          (remote!['id'] as String).compareTo(
                                cursor!.substring(3),
                              ) <=
                              0)
                  ? []
                  : [remote],
            );
          }
          await beforeWrite?.call();
          final candidate = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          if (request.method == 'PATCH') {
            expect(request.url.queryParameters['id'], 'eq.${original.id}');
            expect(
              request.url.queryParameters.containsKey('logical_version'),
              isTrue,
            );
            expect(
              request.url.queryParameters.containsKey('device_id'),
              isTrue,
            );
            if (request.url.queryParameters['logical_version'] !=
                    'eq.${remote?['logical_version']}' ||
                request.url.queryParameters['device_id'] !=
                    'eq.${remote?['device_id']}') {
              return reply([]);
            }
          }
          writes++;
          remote = candidate;
          final response = reply([Map<String, dynamic>.from(candidate)]);
          await afterWrite?.call();
          if (loseResponse) throw StateError('Synthetic response lost');
          return response;
        }
        if (request.url.path.endsWith('/sync_operations')) {
          receipts++;
          return reply([]);
        }
        if (request.url.path.endsWith('/purged_entities') ||
            request.url.path.endsWith('/projects') ||
            request.url.path.endsWith('/project_sections')) {
          return reply([]);
        }
        throw StateError('Unexpected mock endpoint ${request.url.path}');
      }),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'synthetic-token',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'user',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-09-07T00:00:00Z',
        },
      }),
    );
  }

  Future<List<OutboxEntry>> pending() => (db.select(
    db.outboxEntries,
  )..orderBy([(r) => OrderingTerm(expression: r.createdAt)])).get();
  Future<({Map<String, dynamic> row, int retries})> upload() async =>
      TaskSyncWriter(
        db,
        client,
      ).upload(await db.select(db.tasks).getSingle(), await pending());
  Future<void> close() async {
    await client.dispose();
    await db.close();
  }
}

void main() {
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.init();
  });
  tearDown(() => f.close());

  test(
    'il cambio giorno modifica la visibilità senza versioni né outbox',
    () async {
      expect(
        isScheduledDue(f.original.status, f.original.showDate, '2026-09-08'),
        isTrue,
      );
      expect(isScheduledDue('scheduled', null, '2026-09-08'), isFalse);
      expect(isScheduledDue('scheduled', '2026-09-09', '2026-09-08'), isFalse);
      expect(await f.pending(), isEmpty);
      expect(await f.db.select(f.db.tasks).getSingle(), f.original);
    },
  );

  test(
    'una modifica locale non ripristina titolo e data remoti più recenti',
    () async {
      await f.repo.setCompleted(f.original, true);
      f.remote = {
        ...f.remote!,
        'title': 'Titolo remoto',
        'show_date': '2026-09-12',
        'logical_version': 100,
        'device_id': 'web',
      };
      final result = await f.upload();
      expect(result.row['title'], 'Titolo remoto');
      expect(result.row['show_date'], '2026-09-12');
      expect(result.row['status'], 'completed');
      expect(result.row['logical_version'], 101);
    },
  );

  test(
    'un editor aperto prima di un pull conserva i campi non modificati',
    () async {
      await f.db
          .into(f.db.tasks)
          .insertOnConflictUpdate(
            f.original.copyWith(title: 'Titolo remoto', logicalVersion: 80),
          );
      await f.repo.updateDetails(
        f.original,
        title: f.original.title,
        notes: 'Nota modificata',
        showDate: f.original.showDate,
      );
      final row = await f.db.select(f.db.tasks).getSingle();
      expect(row.title, 'Titolo remoto');
      expect(row.notes, 'Nota modificata');
      expect(row.logicalVersion, 81);
      final payload = jsonDecode((await f.pending()).single.payload) as Map;
      expect((payload['changes'] as Map).containsKey('title'), isFalse);
    },
  );

  test('CAS rilegge un cambiamento remoto fra GET e UPDATE', () async {
    await f.repo.move(f.original, domain.TaskStatus.waiting);
    f.beforeWrite = () async {
      f.beforeWrite = null;
      f.remote = {
        ...f.remote!,
        'title': 'Concorrenza preservata',
        'logical_version': 90,
      };
    };
    final result = await f.upload();
    expect(result.retries, 1);
    expect(result.row['title'], 'Concorrenza preservata');
    expect(result.row['status'], 'waiting');
    expect(f.writes, 1);
  });

  test(
    'un retry confermato non riapplica intenti su modifiche remote successive',
    () async {
      await f.repo.move(f.original, domain.TaskStatus.waiting);
      await f.upload();
      f.remote = {...f.remote!, 'status': 'completed', 'logical_version': 99};
      await f.upload();
      expect(f.writes, 1);
      expect(f.remote!['status'], 'completed');
    },
  );

  test(
    'risposta persa riconosciuta senza duplicare una scrittura accettata',
    () async {
      await f.repo.move(f.original, domain.TaskStatus.waiting);
      f.loseResponse = true;
      await expectLater(f.upload(), throwsStateError);
      f.loseResponse = false;
      await f.upload();
      expect(f.writes, 1);
      expect(
        (jsonDecode((await f.pending()).single.payload) as Map)['confirmed'],
        isTrue,
      );
    },
  );

  test(
    'esito incerto e server cambiato conservano outbox e entrambe le versioni',
    () async {
      await f.repo.move(f.original, domain.TaskStatus.waiting);
      f.loseResponse = true;
      await expectLater(f.upload(), throwsStateError);
      f.loseResponse = false;
      f.remote = {...f.remote!, 'status': 'completed', 'logical_version': 99};
      await expectLater(
        f.upload(),
        throwsA(isA<SyncIntentConflictException>()),
      );
      expect(f.writes, 1);
      expect(await f.pending(), hasLength(1));
      final revisions = await (f.db.select(
        f.db.activityRevisions,
      )..where((r) => r.source.equals('sync_conflict'))).get();
      expect(revisions, hasLength(1));
    },
  );

  test('outbox legacy non può ribasare una copia obsoleta', () async {
    await f.db
        .into(f.db.outboxEntries)
        .insert(
          OutboxEntriesCompanion.insert(
            operationId: 'legacy-op',
            entityId: f.original.id,
            operation: 'upsert',
            payload: jsonEncode({'id': f.original.id, 'version': 2}),
            createdAt: 1,
          ),
        );
    f.remote = {...f.remote!, 'title': 'Nuovo remoto', 'logical_version': 100};
    await expectLater(f.upload(), throwsA(isA<SyncIntentConflictException>()));
    expect(f.writes, 0);
    expect(await f.pending(), hasLength(1));
    // Explicit recovery replaces the old unknown intent and unblocks synchronization.
    await f.repo.restoreRevision(taskFromRemote(f.remote!));
    await f.upload();
    expect(f.remote!['title'], 'Nuovo remoto');
  });

  test('una modifica normale non resuscita una tombstone remota', () async {
    await f.repo.move(f.original, domain.TaskStatus.waiting);
    f.remote = {...f.remote!, 'deleted_at': 123, 'logical_version': 100};
    await expectLater(f.upload(), throwsA(isA<SyncIntentConflictException>()));
    expect(f.writes, 0);
  });

  test(
    'modifiche durante invio non vengono riconosciute né sovrascritte dal pull',
    () async {
      await f.repo.move(f.original, domain.TaskStatus.waiting);
      f.afterWrite = () async {
        f.afterWrite = null;
        final current = await f.db.select(f.db.tasks).getSingle();
        await f.repo.updateDetails(
          current,
          title: 'Modifica durante invio',
          notes: current.notes,
          showDate: current.showDate,
        );
      };
      final sync = SyncService(f.db, f.client);
      await sync.sync();
      expect(sync.latest.phase, SyncPhase.current);
      expect(await f.pending(), hasLength(1));
      expect(
        (await f.db.select(f.db.tasks).getSingle()).title,
        'Modifica durante invio',
      );
      await sync.sync();
      expect(await f.pending(), isEmpty);
      expect(f.remote!['title'], 'Modifica durante invio');
      await sync.dispose();
    },
  );

  test('le ricevute tecniche non includono contenuti o snapshot', () async {
    await f.repo.updateDetails(
      f.original,
      title: 'Dato sintetico riservato',
      notes: 'Nota riservata',
      showDate: f.original.showDate,
    );
    await f.upload();
    final encoded = jsonEncode(syncReceipt((await f.pending()).single));
    expect(encoded, isNot(contains('riservat')));
    expect(encoded, isNot(contains('snapshot')));
    expect(encoded, contains('changed_fields'));
  });
}
