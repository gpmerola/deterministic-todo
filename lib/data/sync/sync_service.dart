import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' as domain;
import '../../services/diagnostic_log_service.dart';
import '../local/database.dart';
import 'paged_remote.dart';
import 'project_sync_writer.dart';
import 'task_sync_writer.dart';

enum SyncPhase { disabled, offline, syncing, current, error }

enum SyncStage { idle, projects, taskUpload, receipt, taskPull, taskMerge }

final class SyncWriteVerificationException implements Exception {
  const SyncWriteVerificationException();
}

class SyncSnapshot {
  const SyncSnapshot(
    this.phase, {
    this.pending = 0,
    this.lastSuccess,
    this.error,
    this.stage = SyncStage.idle,
    this.lastFailure,
    this.lastError,
    this.lastFailureStage,
    this.lastRecovery,
    this.retryAt,
    this.consecutiveFailures = 0,
  });
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSuccess;
  final String? error;
  final SyncStage stage;
  final DateTime? lastFailure;
  final String? lastError;
  final SyncStage? lastFailureStage;
  final DateTime? lastRecovery;
  final DateTime? retryAt;
  final int consecutiveFailures;
}

class SyncService {
  SyncService(this.db, this.client);
  static const periodicInterval = Duration(minutes: 10);
  static const eventDebounce = Duration(milliseconds: 120);
  final AppDatabase db;
  final SupabaseClient client;
  final _state = StreamController<SyncSnapshot>.broadcast();
  final _remoteTaskChanges = StreamController<Set<String>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<List<OutboxEntry>>? _outbox;
  RealtimeChannel? _realtime;
  Timer? _timer;
  Timer? _outboxTimer;
  Timer? _realtimeTimer;
  Timer? _realtimeReconnectTimer;
  Timer? _retryTimer;
  Future<void>? _realtimeRemoval;
  Future<void>? _inFlight;
  bool _syncAgain = false;
  bool _pullAllRequested = false;
  bool _paused = false;
  int _consecutiveFailures = 0;
  int _syncCycle = 0;
  DateTime? _lastFailureAt;
  String? _lastError;
  SyncStage? _lastFailureStage;
  DateTime? _lastRecoveryAt;
  Set<String> _observedOutboxOperations = const {};
  final Map<String, Set<String>> _pendingRealtimeIds = {
    'tasks': <String>{},
    'projects': <String>{},
    'project_sections': <String>{},
  };
  SyncSnapshot _latest = const SyncSnapshot(SyncPhase.disabled);
  String? _authenticatedUserId;

  static bool shouldSyncForAuthChange(String? previous, String? next) =>
      next != null && previous != next;

  Stream<SyncSnapshot> get snapshots => _state.stream;
  Stream<Set<String>> get remoteTaskChanges => _remoteTaskChanges.stream;
  SyncSnapshot get latest => _latest;

  void _emit(SyncSnapshot snapshot) {
    _latest = snapshot;
    _state.add(snapshot);
  }

  void start() {
    _authenticatedUserId = client.auth.currentUser?.id;
    _auth = client.auth.onAuthStateChange.listen((state) {
      final nextUserId = state.session?.user.id;
      final shouldSync = shouldSyncForAuthChange(
        _authenticatedUserId,
        nextUserId,
      );
      _authenticatedUserId = nextUserId;
      if (nextUserId != null) {
        unawaited(_subscribeRealtime());
        if (shouldSync) unawaited(sync());
      } else {
        unawaited(_removeRealtime());
        _emit(const SyncSnapshot(SyncPhase.disabled));
      }
    });
    _outbox = db.select(db.outboxEntries).watch().listen((entries) {
      final operations = entries.map((entry) => entry.operationId).toSet();
      final hasNewWork = outboxOperationsChanged(
        _observedOutboxOperations,
        operations,
      );
      _observedOutboxOperations = operations;
      if (entries.isNotEmpty && hasNewWork) _scheduleOutboxSync();
    });
    _connectivity = Connectivity().onConnectivityChanged.listen((result) {
      if (result.contains(ConnectivityResult.none)) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _emit(
          SyncSnapshot(
            SyncPhase.offline,
            pending: _latest.pending,
            lastSuccess: _latest.lastSuccess,
          ),
        );
      } else {
        unawaited(sync());
      }
    });
    if (client.auth.currentUser != null) {
      unawaited(_subscribeRealtime());
      unawaited(sync());
    }
    _startTimer();
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _outboxTimer?.cancel();
    _outboxTimer = null;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_suspendRealtime());
  }

  void resume() {
    _paused = false;
    _startTimer();
    unawaited(_restoreRealtimeAndSync());
  }

  Future<void> _suspendRealtime() {
    final active = _realtimeRemoval;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _removeRealtime().catchError((Object _) {}).whenComplete(() {
      if (identical(_realtimeRemoval, operation)) _realtimeRemoval = null;
    });
    _realtimeRemoval = operation;
    return operation;
  }

  Future<void> _restoreRealtimeAndSync() async {
    await _realtimeRemoval;
    if (_paused || client.auth.currentUser == null) return;
    await _subscribeRealtime();
    if (!_paused) await sync();
  }

  void _startTimer() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(periodicInterval, (_) => unawaited(sync()));
  }

  void _scheduleOutboxSync() {
    if (_paused || client.auth.currentUser == null) return;
    _outboxTimer?.cancel();
    _outboxTimer = Timer(eventDebounce, () => unawaited(sync(pullAll: false)));
  }

  Future<void> _subscribeRealtime() async {
    final user = client.auth.currentUser;
    if (!shouldSubscribeRealtime(
      paused: _paused,
      hasAuthenticatedUser: user != null,
      hasChannel: _realtime != null,
    )) {
      return;
    }
    final authenticatedUser = user!;
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: authenticatedUser.id,
    );
    final channel = client.channel('todo-live-${authenticatedUser.id}');
    for (final table in const ['tasks', 'projects', 'project_sections']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: filter,
        callback: (payload) => _queueRealtimeChange(table, payload),
      );
    }
    _realtime = channel
      ..subscribe((status, error) {
        unawaited(_handleRealtimeStatus(channel, status, error));
      });
  }

  Future<void> _handleRealtimeStatus(
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
    Object? error,
  ) async {
    if (!identical(_realtime, channel)) return;
    unawaited(
      DiagnosticLogService.instance.event(
        'realtime_status',
        level: shouldReconnectRealtime(status) ? 'warning' : 'info',
        fields: {'status': status.name},
      ),
    );
    if (status == RealtimeSubscribeStatus.subscribed) {
      _realtimeReconnectTimer?.cancel();
      _realtimeReconnectTimer = null;
      if (!_paused) unawaited(sync());
      return;
    }
    if (!shouldReconnectRealtime(status)) return;
    _realtime = null;
    try {
      await client.removeChannel(channel);
    } on Object {
      // La riconnessione deve proseguire anche se il vecchio canale è già
      // irraggiungibile o è stato rimosso dal server.
    }
    if (_paused || client.auth.currentUser == null) return;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = Timer(const Duration(seconds: 2), () {
      _realtimeReconnectTimer = null;
      if (!_paused) unawaited(_subscribeRealtime());
    });
  }

  void _queueRealtimeChange(String table, PostgresChangePayload payload) {
    if (_paused) return;
    final id = (payload.newRecord['id'] ?? payload.oldRecord['id']) as String?;
    if (id == null) return;
    _pendingRealtimeIds[table]!.add(id);
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer(
      eventDebounce,
      () => unawaited(_pullQueuedRealtimeChanges()),
    );
  }

  Future<void> _pullQueuedRealtimeChanges() async {
    if (_paused || client.auth.currentUser == null) return;
    final queued = {
      for (final entry in _pendingRealtimeIds.entries)
        entry.key: entry.value.toSet(),
    };
    for (final ids in _pendingRealtimeIds.values) {
      ids.clear();
    }
    try {
      final taskIds = queued['tasks']!;
      final changedTasks = <String>{};
      if (taskIds.isNotEmpty) {
        final remoteRows = await client
            .from('tasks')
            .select()
            .inFilter('id', taskIds.toList());
        final localTasks = await (db.select(
          db.tasks,
        )..where((row) => row.id.isIn(taskIds))).get();
        final localById = {for (final task in localTasks) task.id: task};
        for (final raw in remoteRows) {
          if (await _mergeRemote(raw, localById[raw['id'] as String])) {
            changedTasks.add(raw['id'] as String);
          }
        }
      }
      if (changedTasks.isNotEmpty) _remoteTaskChanges.add(changedTasks);
      if (queued['projects']!.isNotEmpty ||
          queued['project_sections']!.isNotEmpty) {
        await _pullRemoteProjects(
          projectIds: queued['projects']!,
          sectionIds: queued['project_sections']!,
        );
      }
    } on Object {
      // Il controllo periodico recupera qualunque evento perso. Realtime,
      // outbox, connettività e resume restano i percorsi immediati.
    }
  }

  Future<void> _removeRealtime() async {
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    final channel = _realtime;
    _realtime = null;
    if (channel != null) await client.removeChannel(channel);
  }

  Future<void> sync({bool pullAll = true}) {
    if (pullAll) _pullAllRequested = true;
    final active = _inFlight;
    if (active != null) {
      _syncAgain = true;
      return active;
    }
    final operation = _syncUntilQuiet();
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<void> purgeRemoteTrash() async {
    await sync();
    if (_latest.phase != SyncPhase.current ||
        (await db.select(db.outboxEntries).get()).isNotEmpty) {
      throw const SyncWriteVerificationException();
    }
    await client.rpc('purge_trash_v2');
    await _pullPurgedEntities();
  }

  Future<void> _syncUntilQuiet() async {
    do {
      _syncAgain = false;
      final pullAll = _pullAllRequested;
      _pullAllRequested = false;
      await _syncOnce(pullAll: pullAll);
    } while (_syncAgain && !_paused);
  }

  Future<void> _syncOnce({required bool pullAll}) async {
    if (client.auth.currentUser == null) {
      _emit(const SyncSnapshot(SyncPhase.disabled));
      return;
    }
    final entries =
        await (db.select(db.outboxEntries)..orderBy([
              (row) => OrderingTerm(expression: row.createdAt),
              (_) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
              ),
            ]))
            .get();
    final cycle = ++_syncCycle;
    var stage = SyncStage.projects;
    final oldestOutboxAgeMs = syncOutboxOldestAgeMs(
      entries.map((entry) => entry.createdAt),
      DateTime.now().toUtc(),
    );
    _emit(
      SyncSnapshot(
        SyncPhase.syncing,
        pending: entries.length,
        stage: stage,
        consecutiveFailures: _consecutiveFailures,
      ),
    );
    unawaited(
      DiagnosticLogService.instance.event(
        'sync_started',
        fields: {
          'pending': entries.length,
          'cycle_id': cycle,
          'sync_stage': stage.name,
          'outbox_oldest_age_ms': oldestOutboxAgeMs,
          'auth_state': syncAuthState(client.auth.currentSession),
        },
      ),
    );
    final timer = Stopwatch()..start();
    try {
      var conflicts = 0;
      var uploadedEntities = 0;
      var rebasedEntities = 0;
      final grouped = <String, List<OutboxEntry>>{};
      // Parent rows precede tasks, and each entity receives its own acknowledgement.
      for (final entry in entries) {
        grouped
            .putIfAbsent(
              '${isProjectOperation(entry) ? entry.operation : 'tasks'}:${entry.entityId}',
              () => [],
            )
            .add(entry);
      }
      int rank(List<OutboxEntry> group) => group.first.operation == 'projects'
          ? 0
          : group.first.operation == 'project_sections'
          ? 1
          : 2;
      final groups = grouped.values.toList()
        ..sort((a, b) => rank(a).compareTo(rank(b)));
      for (final group in groups) {
        final entry = group.first;
        try {
          Map<String, dynamic> row;
          if (isProjectOperation(entry)) {
            stage = SyncStage.projects;
            row = await ProjectSyncWriter(db, client).upload(group);
          } else {
            stage = SyncStage.taskUpload;
            final task = await (db.select(
              db.tasks,
            )..where((r) => r.id.equals(entry.entityId))).getSingleOrNull();
            if (task == null) throw const SyncIntentConflictException();
            try {
              final result = await TaskSyncWriter(
                db,
                client,
              ).upload(task, group);
              rebasedEntities += result.retries;
              row = result.row;
            } on PostgrestException catch (error) {
              if (isRecurringOccurrenceConflict(error)) {
                await _reconcileRecurringOccurrence(task);
              }
              rethrow;
            }
          }
          stage = SyncStage.receipt;
          await client
              .from('sync_operations')
              .upsert(
                [
                  for (final op in group)
                    {
                      'operation_id': op.operationId,
                      'entity_id': op.entityId,
                      'operation': isProjectOperation(op)
                          ? 'upsert'
                          : op.operation,
                      'payload': syncReceipt(op),
                    },
                ],
                onConflict: 'operation_id',
                ignoreDuplicates: true,
              );
          await db.transaction(() async {
            await (db.delete(db.outboxEntries)..where(
                  (r) => r.operationId.isIn(group.map((e) => e.operationId)),
                ))
                .go();
            if (isProjectOperation(entry)) {
              await _mergeProject(entry.operation, row);
            } else {
              await _mergeRemote(row, null);
            }
          });
          uploadedEntities++;
        } on PostgrestException catch (error) {
          if (error.code != 'P0001' ||
              !error.message.contains('todo_entity_purged')) {
            rethrow;
          }
          conflicts++;
          await (db.update(db.outboxEntries)..where(
                (r) => r.operationId.isIn(group.map((e) => e.operationId)),
              ))
              .write(
                const OutboxEntriesCompanion(lastError: Value('purged_entity')),
              );
        } on SyncIntentConflictException {
          conflicts++;
          await (db.update(db.outboxEntries)..where(
                (r) => r.operationId.isIn(group.map((e) => e.operationId)),
              ))
              .write(
                const OutboxEntriesCompanion(
                  lastError: Value('intent_conflict'),
                ),
              );
        }
      }
      stage = SyncStage.taskPull;
      var remoteCount = 0;
      if (pullAll) {
        await _syncProjects();
        await for (final page in remotePages(client, 'tasks')) {
          stage = SyncStage.taskMerge;
          await db.transaction(() async {
            for (final raw in page) {
              await _mergeRemote(raw, null);
            }
          });
          remoteCount += page.length;
        }
        await _pullPurgedEntities();
      }
      final remaining = await db.select(db.outboxEntries).get();
      conflicts = remaining
          .where(
            (e) =>
                e.lastError == 'intent_conflict' ||
                e.lastError == 'purged_entity',
          )
          .map((e) => e.entityId)
          .toSet()
          .length;
      final now = DateTime.now().toUtc();
      timer.stop();
      final recoveredFailures = _consecutiveFailures;
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      if (recoveredFailures > 0) _lastRecoveryAt = now;
      _emit(
        SyncSnapshot(
          conflicts > 0 ? SyncPhase.error : SyncPhase.current,
          pending: remaining.length,
          error: conflicts > 0
              ? 'Serve una scelta per $conflicts elementi'
              : null,
          lastSuccess: now,
          lastFailure: _lastFailureAt,
          lastError: _lastError,
          lastFailureStage: _lastFailureStage,
          lastRecovery: _lastRecoveryAt,
        ),
      );
      unawaited(
        DiagnosticLogService.instance.event(
          'sync_completed',
          fields: {
            'count': entries.length,
            'cycle_id': cycle,
            'sync_stage': SyncStage.idle.name,
            'uploaded_entities': uploadedEntities,
            'rebased_entities': rebasedEntities,
            'remote_rows': remoteCount,
            'conflicts': conflicts,
            'duration_ms': timer.elapsedMilliseconds,
          },
        ),
      );
      if (recoveredFailures > 0) {
        unawaited(
          DiagnosticLogService.instance.event(
            'sync_recovered',
            fields: {
              'cycle_id': cycle,
              'recovered_failures': recoveredFailures,
              'pending': entries.length,
              'duration_ms': timer.elapsedMilliseconds,
            },
          ),
        );
      }
    } catch (error) {
      timer.stop();
      final errorCode = safeSyncErrorCode(error);
      final failedAt = DateTime.now().toUtc();
      final transient = isTransientSyncError(error);
      final retryDelay = transient ? _scheduleRetry() : null;
      final retryAt = retryDelay == null ? null : failedAt.add(retryDelay);
      final networkState = await safeSyncNetworkState();
      _lastFailureAt = failedAt;
      _lastError = errorCode;
      _lastFailureStage = stage;
      _emit(
        SyncSnapshot(
          SyncPhase.error,
          pending: entries.length,
          error: errorCode,
          stage: stage,
          lastFailure: failedAt,
          lastError: errorCode,
          lastFailureStage: stage,
          lastRecovery: _lastRecoveryAt,
          retryAt: retryAt,
          consecutiveFailures: _consecutiveFailures,
        ),
      );
      if (entries.isNotEmpty) {
        try {
          var nextAttempt = 1;
          for (final entry in entries) {
            if (entry.attempts >= nextAttempt) {
              nextAttempt = entry.attempts + 1;
            }
          }
          await (db.update(db.outboxEntries)..where(
                (row) => row.operationId.isIn(
                  entries.map((entry) => entry.operationId),
                ),
              ))
              .write(
                OutboxEntriesCompanion(
                  attempts: Value(nextAttempt),
                  lastError: Value(errorCode),
                ),
              );
        } on Object {
          // La diagnostica dell'outbox non deve mascherare l'errore originale.
        }
      }
      unawaited(
        DiagnosticLogService.instance.event(
          'sync_failed',
          level: 'error',
          fields: {
            'pending': entries.length,
            'cycle_id': cycle,
            'sync_stage': stage.name,
            'error_type': error.runtimeType.toString(),
            if (error is PostgrestException) 'error_code': error.code,
            'error_class': safeSyncErrorClass(error),
            'network_state': networkState,
            'auth_state': syncAuthState(client.auth.currentSession),
            'failure_index': _consecutiveFailures,
            'retry_delay_ms': retryDelay?.inMilliseconds,
            'retry_at': retryAt?.toIso8601String(),
            'outbox_oldest_age_ms': oldestOutboxAgeMs,
            'duration_ms': timer.elapsedMilliseconds,
          },
        ),
      );
    }
  }

  Duration? _scheduleRetry() {
    if (_paused || client.auth.currentUser == null) return null;
    _retryTimer?.cancel();
    final delay = syncRetryDelay(_consecutiveFailures++);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_paused) unawaited(sync());
    });
    return delay;
  }

  Future<void> _syncProjects() async {
    for (final table in ['projects', 'project_sections']) {
      await for (final page in remotePages(client, table)) {
        for (final raw in page) {
          await _mergeProject(table, raw);
        }
      }
    }
  }

  Future<void> _pullRemoteProjects({
    required Set<String> projectIds,
    required Set<String> sectionIds,
  }) async {
    for (final group in {
      'projects': projectIds,
      'project_sections': sectionIds,
    }.entries) {
      final ids = group.value.toList();
      for (var start = 0; start < ids.length; start += 100) {
        final batch = ids.skip(start).take(100).toList();
        for (final raw
            in await client.from(group.key).select().inFilter('id', batch)) {
          await _mergeProject(group.key, raw);
        }
      }
    }
  }

  Future<void> _mergeProject(
    String table,
    Map<String, dynamic> raw,
  ) => db.withRevisionSource('sync_pull', () async {
    final id = raw['id'] as String;
    if (await _wasPurged(table, id)) return;
    final pending =
        await (db.select(db.outboxEntries)
              ..where((r) => r.entityId.equals(id) & r.operation.equals(table))
              ..limit(1))
            .get();
    if (pending.isNotEmpty) return;
    await _observeLogicalCounter(raw['logical_version'] as int);
    final old = await db
        .customSelect(
          'SELECT logical_version, device_id FROM "$table" WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (old != null &&
        domain.LogicalVersion(
              raw['logical_version'] as int,
              raw['device_id'] as String,
            ).compareTo(
              domain.LogicalVersion(
                old.read<int>('logical_version'),
                old.read<String>('device_id'),
              ),
            ) <=
            0) {
      return;
    }
    final json = <String, dynamic>{
      for (final e in normalizeProject(raw).entries)
        e.key.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase()):
            e.value,
    };
    if (table == 'projects') {
      await db.into(db.projects).insertOnConflictUpdate(Project.fromJson(json));
    } else {
      await db
          .into(db.projectSections)
          .insertOnConflictUpdate(ProjectSection.fromJson(json));
    }
  });

  Future<bool> _wasPurged(String table, String id) async =>
      await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('purged:$table:$id'))).getSingleOrNull() !=
      null;

  /// Older servers remain usable, but cannot perform the new safe purge.
  Future<void> _pullPurgedEntities() async {
    try {
      await for (final page in remotePages(client, 'purged_entities')) {
        await db.withRevisionSource('sync_purge', () async {
          for (final row in page) {
            final table = row['entity_type'] as String;
            if (!const {
              'tasks',
              'projects',
              'project_sections',
            }.contains(table)) {
              throw const FormatException('Invalid purge type');
            }
            final id = row['entity_id'] as String;
            await db
                .into(db.appSettings)
                .insert(
                  AppSettingsCompanion.insert(
                    key: 'purged:$table:$id',
                    value: '1',
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
            await db.customUpdate(
              'DELETE FROM "$table" WHERE id = ?',
              variables: [Variable(id)],
              updates: {db.tasks, db.projects, db.projectSections},
            );
            await (db.delete(
              db.outboxEntries,
            )..where((r) => r.entityId.equals(id))).go();
          }
        });
      }
    } on PostgrestException catch (e) {
      if (!const {'42P01', 'PGRST205'}.contains(e.code)) rethrow;
    }
  }

  Future<bool> _mergeRemote(
    Map<String, dynamic> raw,
    Task? ignoredSnapshot,
  ) => db.withRevisionSource('sync_pull', () async {
    final id = raw['id'] as String;
    if (await _wasPurged('tasks', id)) return false;
    await _observeLogicalCounter(raw['logical_version'] as int);
    final pending =
        await (db.select(db.outboxEntries)
              ..where((row) => row.entityId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) return false;
    // Check and write inside the same transaction; never trust a pre-network snapshot.
    final local = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final remoteVersion = domain.LogicalVersion(
      raw['logical_version'] as int,
      raw['device_id'] as String,
    );
    if (local != null &&
        remoteVersion.compareTo(
              domain.LogicalVersion(local.logicalVersion, local.deviceId),
            ) <=
            0) {
      return false;
    }
    await db
        .into(db.tasks)
        .insertOnConflictUpdate(taskFromRemote(raw).toCompanion(false));
    return true;
  });

  Future<void> _observeLogicalCounter(int counter) => db.transaction(() async {
    final current =
        await (db.select(db.appSettings)
              ..where((row) => row.key.equals('sync_lamport_counter')))
            .getSingleOrNull();
    final saved = int.tryParse(current?.value ?? '') ?? 0;
    if (counter <= saved) return;
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'sync_lamport_counter',
            value: counter.toString(),
          ),
        );
  });

  Future<bool> _reconcileRecurringOccurrence(Task local) async {
    final seriesId = local.seriesId;
    final occurrenceKey = local.occurrenceKey;
    if (seriesId == null || occurrenceKey == null) return false;

    final rows = await client
        .from('tasks')
        .select()
        .eq('series_id', seriesId)
        .eq('occurrence_key', occurrenceKey)
        .limit(1);
    if (rows.isEmpty) return false;
    final remote = Map<String, dynamic>.from(rows.first);
    final remoteId = remote['id'] as String;
    if (remoteId == local.id) return false;

    await db.recordSyncRevision(
      entityId: local.id,
      source: 'sync_conflict',
      before: remote,
      after: taskToRemote(local, client.auth.currentUser!.id),
      operationIds:
          (await (db.select(
                db.outboxEntries,
              )..where((row) => row.entityId.equals(local.id))).get())
              .map((row) => row.operationId)
              .toList(),
    );
    throw const SyncIntentConflictException();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _outboxTimer?.cancel();
    _realtimeTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivity?.cancel();
    await _auth?.cancel();
    await _outbox?.cancel();
    await _removeRealtime();
    await _state.close();
    await _remoteTaskChanges.close();
  }
}

Set<String> distinctEntityIds(Iterable<String> ids) => ids.toSet();

Duration syncRetryDelay(int failureIndex) {
  const delays = [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];
  return delays[failureIndex.clamp(0, delays.length - 1)];
}

int? syncOutboxOldestAgeMs(Iterable<int> createdAtMicros, DateTime now) {
  if (createdAtMicros.isEmpty) return null;
  final oldest = createdAtMicros.reduce(
    (left, right) => left < right ? left : right,
  );
  final age = now.microsecondsSinceEpoch - oldest;
  return age <= 0 ? 0 : age ~/ Duration.microsecondsPerMillisecond;
}

String syncAuthState(Session? session, {DateTime? now}) {
  if (session == null) return 'missing';
  final expiresAt = session.expiresAt;
  if (expiresAt == null) return 'active_unknown_expiry';
  final seconds =
      (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  if (expiresAt <= seconds) return 'expired';
  if (expiresAt - seconds <= 60) return 'near_expiry';
  return 'active';
}

Future<String> safeSyncNetworkState() async {
  try {
    final result = await Connectivity().checkConnectivity();
    if (result.isEmpty || result.contains(ConnectivityResult.none)) {
      return 'none';
    }
    return result.map((item) => item.name).toSet().join('+');
  } on Object {
    return 'unknown';
  }
}

String safeSyncErrorClass(Object error) {
  if (error is SyncIntentConflictException) return 'intent_conflict';
  if (error is SyncConcurrentWriteException) return 'concurrent_write';
  if (error is SyncWriteVerificationException) return 'write_verification';
  if (error is PostgrestException) return 'supabase';
  final type = error.runtimeType.toString().toLowerCase();
  if (type.contains('retryablefetch')) return 'auth_transport';
  if (type.contains('timeout')) return 'timeout';
  if (type.contains('socket') ||
      type.contains('network') ||
      type.contains('connection') ||
      type.contains('handshake') ||
      type.contains('clientexception')) {
    return 'network';
  }
  return 'unexpected';
}

bool outboxOperationsChanged(Set<String> previous, Set<String> current) =>
    previous.length != current.length || !previous.containsAll(current);

bool isRecurringOccurrenceConflict(PostgrestException error) =>
    error.code == '23505' &&
    error.message.contains('tasks_user_id_series_id_occurrence_key_key');

bool shouldReconnectRealtime(RealtimeSubscribeStatus status) =>
    switch (status) {
      RealtimeSubscribeStatus.channelError ||
      RealtimeSubscribeStatus.closed ||
      RealtimeSubscribeStatus.timedOut => true,
      RealtimeSubscribeStatus.subscribed => false,
    };

bool shouldSubscribeRealtime({
  required bool paused,
  required bool hasAuthenticatedUser,
  required bool hasChannel,
}) => !paused && hasAuthenticatedUser && !hasChannel;

bool isTransientSyncError(Object error) {
  if (error is SyncConcurrentWriteException) return true;
  if (error is SyncWriteVerificationException) return true;
  final type = error.runtimeType.toString().toLowerCase();
  if (type.contains('socket') ||
      type.contains('clientexception') ||
      type.contains('timeout') ||
      type.contains('handshake') ||
      type.contains('network') ||
      type.contains('connection') ||
      type.contains('retryablefetch')) {
    return true;
  }
  if (error is PostgrestException) {
    return const {
      'PGRST000',
      'PGRST001',
      'PGRST002',
      'PGRST003',
    }.contains(error.code);
  }
  return false;
}

String safeSyncErrorCode(Object error) {
  if (error is SyncIntentConflictException) {
    return 'Conflitto: scegli la versione nello storico attività';
  }
  if (error is PostgrestException) return 'Supabase ${error.code}';
  final type = error.runtimeType.toString();
  if (isTransientSyncError(error)) return 'Rete $type';
  return type;
}
