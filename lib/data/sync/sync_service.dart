import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' show LogicalVersion;
import '../../services/diagnostic_log_service.dart';
import '../local/database.dart';
import 'paged_remote.dart';
import 'project_sync_writer.dart';
import 'purge_batch_merge.dart';
import 'realtime_versions.dart';
import 'remote_batch_merge.dart';
import 'sync_connection.dart';
import 'sync_overview.dart';
import 'sync_policy.dart';
import 'sync_request_scope.dart';
import 'sync_status.dart';
import 'task_fingerprints.dart';
import 'task_sync_writer.dart';

export 'realtime_versions.dart';
export 'sync_policy.dart';
export 'sync_status.dart';

class SyncService {
  SyncService(this.db, this.client);
  static const periodicInterval = Duration(minutes: 10);
  static const eventDebounce = Duration(milliseconds: 120);

  /// Keeps `id=in.(...)` URLs well below common proxy limits.
  static const idBatchSize = 100;
  static const receiptBatchSize = 200;
  final AppDatabase db;
  final SupabaseClient client;
  final _state = StreamController<SyncSnapshot>.broadcast();
  final _remoteTaskChanges = StreamController<Set<String>>.broadcast();
  StreamSubscription<Set<String>>? _outbox;
  Timer? _timer;
  Timer? _outboxTimer;
  Timer? _realtimeTimer;
  Timer? _retryTimer;
  Future<void>? _realtimeRemoval;
  Future<void>? _inFlight;
  bool _disposed = false;
  bool _started = false;
  Future<void>? _disposing;
  final _scopes = <SyncRequestScope>{};
  final _operations = <Future<void>>{};
  static final _scopeKey = Object();
  SyncRequestScope get _requests => Zone.current[_scopeKey] as SyncRequestScope;

  Future<void> _runScoped(
    Future<void> Function() body, {
    bool cancelIsSuccess = true,
  }) {
    if (_disposed) {
      return cancelIsSuccess
          ? Future.value()
          : Future.error(const SyncCancelled());
    }
    final scope = SyncRequestScope(client);
    _scopes.add(scope);
    late final Future<void> operation;
    operation =
        runZoned(() async {
          try {
            await body();
            scope.check();
          } on Object {
            if (scope.isActive) rethrow;
            if (!cancelIsSuccess) throw const SyncCancelled();
          } finally {
            _scopes.remove(scope);
          }
        }, zoneValues: {_scopeKey: scope}).whenComplete(() {
          _operations.remove(operation);
        });
    _operations.add(operation);
    return operation;
  }

  void _cancelRequests() {
    for (final scope in _scopes) {
      scope.cancel();
    }
  }

  bool _syncAgain = false;
  bool _activePullAll = false;
  bool _activeSnapshotStarted = false;
  bool _activeHasUploads = false;
  bool _pullAllRequested = false;
  SyncAlignment? _alignment;
  bool _paused = false;
  bool _flushUploads = false;
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

  /// Highest version announced per queued ID; null when an event had none
  /// (for example a delete), which always requires a fetch.
  final Map<String, Map<String, LogicalVersion?>> _announcedVersions = {
    'tasks': {},
    'projects': {},
    'project_sections': {},
  };
  SyncSnapshot _latest = const SyncSnapshot(SyncPhase.disabled);
  String? _authenticatedUserId;

  static bool shouldSyncForAuthChange(String? previous, String? next) =>
      next != null && previous != next;

  @visibleForTesting
  bool get isPaused => _paused;

  Stream<SyncSnapshot> get snapshots => _state.stream;
  Stream<Set<String>> get remoteTaskChanges => _remoteTaskChanges.stream;
  SyncSnapshot get latest => _latest;

  void _emit(SyncSnapshot snapshot) {
    if (_disposed) return;
    // Every phase carries the last measured alignment; only a sync updates it.
    if (snapshot.alignment == null && _alignment != null) {
      snapshot = SyncSnapshot(
        snapshot.phase,
        pending: snapshot.pending,
        lastSuccess: snapshot.lastSuccess,
        error: snapshot.error,
        stage: snapshot.stage,
        lastFailure: snapshot.lastFailure,
        lastError: snapshot.lastError,
        lastFailureStage: snapshot.lastFailureStage,
        lastRecovery: snapshot.lastRecovery,
        retryAt: snapshot.retryAt,
        consecutiveFailures: snapshot.consecutiveFailures,
        alignment: _alignment,
      );
    }
    _latest = snapshot;
    _state.add(snapshot);
  }

  late final _connection = SyncConnection(
    client,
    isActive: () => !_disposed && !_paused,
    onAuth: _onAuth,
    onOffline: () {
      _retryTimer?.cancel();
      _retryTimer = null;
      _emit(
        SyncSnapshot(
          SyncPhase.offline,
          pending: _latest.pending,
          lastSuccess: _latest.lastSuccess,
        ),
      );
    },
    onOnline: () => unawaited(sync()),
    onSubscribed: () => unawaited(sync(freshSnapshot: true)),
    onRecord: _queueRealtimeChange,
  );

  void _onAuth(AuthState state) {
    if (_disposed) return;
    final nextUserId = state.session?.user.id;
    if (nextUserId != _authenticatedUserId) {
      _cancelRequests();
      for (final ids in _pendingRealtimeIds.values) {
        ids.clear();
      }
      for (final versions in _announcedVersions.values) {
        versions.clear();
      }
      unawaited(_removeRealtime());
    }
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
  }

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _authenticatedUserId = client.auth.currentUser?.id;
    _connection.start();
    _outbox = db.watchOutboxOperationIds().listen((operations) {
      final hasNewWork = outboxOperationsChanged(
        _observedOutboxOperations,
        operations,
      );
      _observedOutboxOperations = operations;
      if (operations.isNotEmpty && hasNewWork) _scheduleOutboxSync();
    });
    // Started in background: [resume] performs the first check and timer.
    if (_paused) return;
    if (client.auth.currentUser != null) {
      unawaited(_subscribeRealtime());
      unawaited(sync());
    }
    _startTimer();
  }

  void pause() {
    if (_disposed || _paused) return;
    // A debounced edit, or one queued behind the active cycle, is sent now
    // instead of waiting for the next foreground: the other device sees it.
    final unsentEdits =
        _outboxTimer?.isActive == true || (_inFlight != null && _syncAgain);
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _outboxTimer?.cancel();
    _outboxTimer = null;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_suspendRealtime());
    if (unsentEdits && client.auth.currentUser != null) {
      _flushUploads = true;
      unawaited(sync(pullAll: false));
    } else if (_inFlight != null && !_activeHasUploads) {
      // A read-only check started by a brief foreground (for example the
      // unlock screen showing this app for a second) would otherwise run on
      // in background and fail when Android restricts the process. Resume
      // performs a new full check; uploads in flight are never cancelled.
      _cancelRequests();
    }
  }

  /// Only undoes [pause]. A transient interruption that never paused (for
  /// example a system dialog) must not rebuild Realtime or rescan the server.
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _flushUploads = false;
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
    if (_disposed || _paused || client.auth.currentUser == null) return;
    await _subscribeRealtime();
    if (!_disposed && !_paused) await sync();
  }

  void _startTimer() {
    if (_disposed || _timer?.isActive == true) return;
    _timer = Timer.periodic(periodicInterval, (_) => unawaited(sync()));
  }

  void _scheduleOutboxSync() {
    if (_disposed || _paused || client.auth.currentUser == null) return;
    _outboxTimer?.cancel();
    _outboxTimer = Timer(eventDebounce, () => unawaited(sync(pullAll: false)));
  }

  Future<void> _subscribeRealtime() => _connection.subscribe();

  void _queueRealtimeChange(String table, PostgresChangePayload payload) =>
      _queueRealtimeRecord(table, payload.newRecord, payload.oldRecord);

  void _queueRealtimeRecord(
    String table,
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    if (_disposed || _paused) return;
    final id = (newRecord['id'] ?? oldRecord['id']) as String?;
    if (id == null) return;
    _pendingRealtimeIds[table]!.add(id);
    final versions = _announcedVersions[table]!;
    final next = announcedVersion(newRecord);
    final previous = versions[id];
    if (!versions.containsKey(id)) {
      versions[id] = next;
    } else if (previous != null &&
        (next == null || next.compareTo(previous) > 0)) {
      versions[id] = next;
    }
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer(
      eventDebounce,
      () => unawaited(_pullQueuedRealtimeChanges()),
    );
  }

  /// Delivers synthetic Realtime notifications without a live channel.
  /// [records] are the announced new rows; bare [ids] announce no version.
  @visibleForTesting
  Future<void> pullRealtimeChangesForTesting(
    String table,
    Iterable<String> ids, {
    Iterable<Map<String, dynamic>> records = const [],
  }) {
    for (final id in ids) {
      _queueRealtimeRecord(table, {'id': id}, const {});
    }
    for (final record in records) {
      _queueRealtimeRecord(table, record, const {});
    }
    _realtimeTimer?.cancel();
    return _pullQueuedRealtimeChanges();
  }

  Future<void> _pullQueuedRealtimeChanges() =>
      _runScoped(_pullQueuedRealtimeChangesScoped);

  Future<void> _pullQueuedRealtimeChangesScoped() async {
    if (_disposed || _paused || client.auth.currentUser == null) return;
    final queued = {
      for (final entry in _pendingRealtimeIds.entries)
        entry.key: entry.value.toSet(),
    };
    final announced = {
      for (final entry in _announcedVersions.entries)
        entry.key: Map<String, LogicalVersion?>.from(entry.value),
    };
    for (final ids in _pendingRealtimeIds.values) {
      ids.clear();
    }
    for (final versions in _announcedVersions.values) {
      versions.clear();
    }
    try {
      for (final table in queued.keys) {
        queued[table] = await realtimeIdsToFetch(
          db,
          table,
          queued[table]!,
          announced[table]!,
        );
      }
      final changedTasks = <String>{};
      final taskIds = queued['tasks']!.toList();
      for (var start = 0; start < taskIds.length; start += idBatchSize) {
        final remoteRows = await _requests.send(
          client
              .from('tasks')
              .select()
              .inFilter('id', taskIds.skip(start).take(idBatchSize).toList()),
        );
        changedTasks.addAll(
          await mergeRemoteBatch(db, 'tasks', remoteRows, _requests),
        );
      }
      if (!_disposed && changedTasks.isNotEmpty) {
        _remoteTaskChanges.add(changedTasks);
      }
      if (queued['projects']!.isNotEmpty ||
          queued['project_sections']!.isNotEmpty) {
        await _pullRemoteProjects(
          projectIds: queued['projects']!,
          sectionIds: queued['project_sections']!,
        );
      }
    } on Object {
      // Gli ID sono già stati tolti dalla coda: senza un controllo completo
      // l'evento resterebbe perso fino al timer periodico. Il controllo a
      // impronte recupera anche righe mai notificate; errori di rete seguono
      // il backoff ordinario.
      if (_requests.isActive && !_disposed && !_paused) unawaited(sync());
    }
  }

  Future<void> _removeRealtime() => _connection.disconnect();

  /// [freshSnapshot] requires a remote read that starts after this call. A
  /// full check whose remote snapshot is already under way cannot satisfy it.
  Future<void> sync({bool pullAll = true, bool freshSnapshot = false}) {
    if (_disposed) return Future.value();
    final active = _inFlight;
    if (active != null) {
      // Join an existing full check. Startup/auth/connectivity must not queue
      // another identical scan. New outbox work still gets a trailing upload.
      if (!pullAll ||
          !_activePullAll ||
          (freshSnapshot && _activeSnapshotStarted)) {
        _syncAgain = true;
        if (pullAll) _pullAllRequested = true;
      }
      return active;
    }
    if (pullAll) _pullAllRequested = true;
    final operation = _syncUntilQuiet();
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  /// Explicit user repair: the next full check ignores bucket fingerprints
  /// and rewrites every remote row with an equal or newer version. Pending
  /// local changes still win; nothing is deleted or uploaded implicitly.
  Future<void> repairAlignment() async {
    if (_disposed) return;
    await (db.delete(
      db.appSettings,
    )..where((r) => r.key.equals(remoteNullRepairKey))).go();
    await sync(freshSnapshot: true);
  }

  Future<void> purgeRemoteTrash() =>
      _runScoped(_purgeRemoteTrashScoped, cancelIsSuccess: false);

  Future<void> _purgeRemoteTrashScoped() async {
    await sync();
    if (_latest.phase != SyncPhase.current ||
        (await db.select(db.outboxEntries).get()).isNotEmpty) {
      throw const SyncWriteVerificationException();
    }
    await _requests.send(client.rpc('purge_trash_v2'));
    await _pullPurgedEntities();
  }

  Future<void> _syncUntilQuiet() async {
    try {
      do {
        _syncAgain = false;
        // While paused only pending uploads are flushed; the full check
        // stays requested for the next foreground cycle.
        final pullAll = _pullAllRequested && !_paused;
        if (pullAll) _pullAllRequested = false;
        _activePullAll = pullAll;
        _activeSnapshotStarted = false;
        _activeHasUploads = true; // Until the cycle has read the outbox.
        await _runScoped(() => _syncOnce(pullAll: pullAll));
      } while (_syncAgain && !_disposed && (!_paused || _flushUploads));
    } finally {
      if (_paused) _flushUploads = false;
    }
  }

  void _reportProgress(
    int cycle,
    SyncStage stage,
    int pending, {
    int remoteRows = 0,
  }) {
    _requests.check();
    _emit(
      SyncSnapshot(
        SyncPhase.syncing,
        pending: pending,
        stage: stage,
        lastSuccess: _latest.lastSuccess,
      ),
    );
    unawaited(
      DiagnosticLogService.instance.event(
        'sync_progress',
        fields: {
          'cycle_id': cycle,
          'sync_stage': stage.name,
          'pending': pending,
          'remote_rows': remoteRows,
          ..._requests.pullDiagnostics,
        },
      ),
    );
  }

  Future<void> _syncOnce({required bool pullAll}) async {
    if (client.auth.currentUser == null) {
      _emit(const SyncSnapshot(SyncPhase.disabled));
      return;
    }
    _requests.check();
    final entries =
        await (db.select(db.outboxEntries)..orderBy([
              (row) => OrderingTerm(expression: row.createdAt),
              (_) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
              ),
            ]))
            .get();
    _requests.check();
    _activeHasUploads = entries.isNotEmpty;
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
          'pull_all': pullAll,
          'outbox_oldest_age_ms': oldestOutboxAgeMs,
          'auth_state': syncAuthState(client.auth.currentSession),
        },
      ),
    );
    final timer = Stopwatch()..start();
    final isolated = <String>{};
    try {
      var uploadedEntities = 0;
      final rejectedCodes = <String>{};
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
      final accepted =
          <({List<OutboxEntry> group, Map<String, dynamic> row})>[];
      try {
        final prefetched = await _prefetchTasks(
          groups
              .where((group) => !isProjectOperation(group.first))
              .map((group) => group.first.entityId),
        );
        for (final group in groups) {
          _requests.check();
          final entry = group.first;
          try {
            Map<String, dynamic> row;
            if (isProjectOperation(entry)) {
              stage = SyncStage.projects;
              row = await ProjectSyncWriter(
                db,
                client,
                scope: _requests,
              ).upload(group);
            } else {
              stage = SyncStage.taskUpload;
              final task = await (db.select(
                db.tasks,
              )..where((r) => r.id.equals(entry.entityId))).getSingleOrNull();
              if (task == null) throw const SyncIntentConflictException();
              try {
                final result =
                    await TaskSyncWriter(db, client, scope: _requests).upload(
                      task,
                      group,
                      prefetched: prefetched.containsKey(task.id)
                          ? (row: prefetched[task.id])
                          : null,
                    );
                rebasedEntities += result.retries;
                row = result.row;
              } on PostgrestException catch (error) {
                if (isRecurringOccurrenceConflict(error)) {
                  await _reconcileRecurringOccurrence(task);
                }
                rethrow;
              }
            }
            accepted.add((group: group, row: row));
            uploadedEntities++;
          } on PostgrestException catch (error) {
            final String marker;
            if (error.code == 'P0001' &&
                error.message.contains('todo_entity_purged')) {
              marker = 'purged_entity';
            } else if (isEntityRejection(error)) {
              // One invalid row must not stop other uploads or the pull.
              marker = 'server_rejected';
              rejectedCodes.add(error.code!);
            } else {
              rethrow;
            }
            await _markGroup(group, marker, isolated);
          } on SyncIntentConflictException {
            await _markGroup(group, 'intent_conflict', isolated);
          }
        }
      } on Object {
        // Server writes already accepted stay confirmed in the outbox either
        // way; acknowledging them now just avoids re-reading them later.
        if (accepted.isNotEmpty && _requests.isActive) {
          try {
            await _acknowledge(accepted);
          } on Object {
            // The original failure is the one reported.
          }
        }
        rethrow;
      }
      if (accepted.isNotEmpty) {
        stage = SyncStage.receipt;
        await _acknowledge(accepted);
      }
      stage = SyncStage.taskPull;
      var remoteCount = 0;
      int? divergedBuckets;
      if (pullAll) {
        _activeSnapshotStarted = true;
        stage = SyncStage.overview;
        _reportProgress(cycle, stage, entries.length);
        final overview = await SyncOverview.fetch(client, _requests);
        final repair = await needsRemoteNullRepair(db);
        stage = SyncStage.projects;
        _reportProgress(cycle, stage, entries.length);
        await _syncProjects(repair ? null : overview);
        stage = SyncStage.taskPull;
        _reportProgress(cycle, stage, entries.length);
        // v2 fingerprints include content, so a row diverged at an equal
        // version changes its bucket. v1 servers compare stamps only and
        // need a complete pull (repair) to rewrite such rows.
        final changed = repair
            ? null
            : await changedTaskBuckets(
                db,
                client,
                _requests,
                fingerprints: overview?.tasks,
                version: overview?.taskVersion ?? taskFingerprintV1,
              );
        final buckets = changed?.buckets;
        for (final bucket in buckets ?? <String?>[null]) {
          await for (final page in remotePages(
            client,
            'tasks',
            scope: _requests,
            idPrefix: bucket,
          )) {
            stage = SyncStage.taskMerge;
            _reportProgress(
              cycle,
              stage,
              entries.length,
              remoteRows: remoteCount,
            );
            await mergeRemoteBatch(db, 'tasks', page, _requests);
            remoteCount += page.length;
            stage = SyncStage.taskPull;
            _reportProgress(
              cycle,
              stage,
              entries.length,
              remoteRows: remoteCount,
            );
          }
        }
        if (repair) await markRemoteNullRepaired(db);
        if (changed != null) {
          divergedBuckets = await unresolvedTaskBuckets(
            db,
            changed.remote,
            changed.buckets,
            _requests,
            version: changed.version,
          );
          _alignment = SyncAlignment(
            divergedBuckets,
            checkedAt: DateTime.now().toUtc(),
            contentChecked: changed.version >= taskFingerprintV2,
          );
        } else if (repair && overview != null) {
          // After the complete pull, measure every server bucket once.
          divergedBuckets = await unresolvedTaskBuckets(
            db,
            overview.tasks,
            [
              for (final item in overview.tasks)
                (item as Map)['bucket'] as String,
            ],
            _requests,
            version: overview.taskVersion,
          );
          _alignment = SyncAlignment(
            divergedBuckets,
            checkedAt: DateTime.now().toUtc(),
            contentChecked: overview.taskVersion >= taskFingerprintV2,
            repaired: true,
          );
        }
        stage = SyncStage.purgePull;
        _reportProgress(cycle, stage, entries.length, remoteRows: remoteCount);
        if (overview == null ||
            !await overview.matches(db, 'purged_entities', _requests)) {
          await _pullPurgedEntities();
        }
      }
      final remaining = await db.select(db.outboxEntries).get();
      _requests.check();
      final conflicts = remaining
          .where(
            (e) =>
                e.lastError == 'intent_conflict' ||
                e.lastError == 'purged_entity',
          )
          .map((e) => e.entityId)
          .toSet()
          .length;
      final rejected = remaining
          .where((e) => e.lastError == 'server_rejected')
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
          conflicts + rejected > 0 ? SyncPhase.error : SyncPhase.current,
          pending: remaining.length,
          error: conflicts > 0
              ? 'Serve una scelta per $conflicts elementi'
              : rejected > 0
              ? 'Rifiutati dal server: $rejected elementi'
              : null,
          lastSuccess: now,
          lastFailure: _lastFailureAt,
          lastError: _lastError,
          lastFailureStage: _lastFailureStage,
          lastRecovery: _lastRecoveryAt,
          alignment: _alignment,
        ),
      );
      unawaited(
        DiagnosticLogService.instance.event(
          'sync_completed',
          fields: {
            'count': entries.length,
            'cycle_id': cycle,
            'sync_stage': SyncStage.idle.name,
            'pending': remaining.length,
            'auth_state': syncAuthState(client.auth.currentSession),
            'request_count': _requests.requestCount,
            'network_ms': _requests.networkMs,
            'comparison_ms': _requests.comparisonMs,
            'purge_ms': _requests.purgeMs,
            'uploaded_entities': uploadedEntities,
            'rebased_entities': rebasedEntities,
            'remote_rows': remoteCount,
            'conflicts': conflicts,
            'rejected': rejected,
            'diverged_buckets': ?divergedBuckets,
            if (rejectedCodes.isNotEmpty)
              'rejected_codes': (rejectedCodes.toList()..sort()).join(','),
            'pull_all': pullAll,
            ..._requests.pullDiagnostics,
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
      if (!_requests.isActive) {
        unawaited(
          DiagnosticLogService.instance.event(
            'sync_cancelled',
            fields: {
              'cycle_id': cycle,
              'sync_stage': stage.name,
              'pending': entries.length,
            },
          ),
        );
        return;
      }
      timer.stop();
      final errorCode = safeSyncErrorCode(error);
      final failedAt = DateTime.now().toUtc();
      final transient = isTransientSyncError(error);
      final retryDelay = transient ? _scheduleRetry() : null;
      final retryAt = retryDelay == null ? null : failedAt.add(retryDelay);
      final networkState = await safeSyncNetworkState();
      if (!_requests.isActive) return;
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
      final unmarked = entries
          .where((entry) => !isolated.contains(entry.operationId))
          .toList();
      if (unmarked.isNotEmpty) {
        try {
          var nextAttempt = 1;
          for (final entry in entries) {
            if (entry.attempts >= nextAttempt) {
              nextAttempt = entry.attempts + 1;
            }
          }
          await (db.update(db.outboxEntries)..where(
                (row) => row.operationId.isIn(
                  unmarked.map((entry) => entry.operationId),
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
            'error_type': safeSyncErrorType(error),
            if (error is PostgrestException) 'error_code': error.code,
            'error_class': safeSyncErrorClass(error),
            'pull_all': pullAll,
            ..._requests.pullDiagnostics,
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

  /// Remote rows for the task groups of this cycle, `null` when absent.
  /// One request per [idBatchSize] entities instead of one per entity.
  Future<Map<String, Map<String, dynamic>?>> _prefetchTasks(
    Iterable<String> ids,
  ) async {
    final pending = ids.toSet().toList();
    final result = <String, Map<String, dynamic>?>{};
    for (var start = 0; start < pending.length; start += idBatchSize) {
      final batch = pending.skip(start).take(idBatchSize).toList();
      final rows = await _requests.send(
        client.from('tasks').select().inFilter('id', batch),
      );
      for (final id in batch) {
        result[id] = null;
      }
      for (final row in rows) {
        result[row['id'] as String] = Map<String, dynamic>.from(row);
      }
    }
    return result;
  }

  /// Receipts in bulk, then one local transaction that removes exactly the
  /// captured operation IDs and merges the accepted rows.
  Future<void> _acknowledge(
    List<({List<OutboxEntry> group, Map<String, dynamic> row})> accepted,
  ) async {
    final receipts = [
      for (final item in accepted)
        for (final op in item.group)
          {
            'operation_id': op.operationId,
            'entity_id': op.entityId,
            'operation': isProjectOperation(op) ? 'upsert' : op.operation,
            'payload': syncReceipt(op),
          },
    ];
    for (var start = 0; start < receipts.length; start += receiptBatchSize) {
      await _requests.send(
        client
            .from('sync_operations')
            .upsert(
              receipts.skip(start).take(receiptBatchSize).toList(),
              onConflict: 'operation_id',
              ignoreDuplicates: true,
            ),
      );
    }
    _requests.check();
    await db.transaction(() async {
      _requests.check();
      await (db.delete(db.outboxEntries)..where(
            (r) => r.operationId.isIn(
              receipts.map((receipt) => receipt['operation_id'] as String),
            ),
          ))
          .go();
      for (final table in const ['projects', 'project_sections', 'tasks']) {
        final rows = [
          for (final item in accepted)
            if ((isProjectOperation(item.group.first)
                    ? item.group.first.operation
                    : 'tasks') ==
                table)
              item.row,
        ];
        if (rows.isNotEmpty) await mergeRemoteBatch(db, table, rows, _requests);
      }
    });
  }

  Future<void> _markGroup(
    List<OutboxEntry> group,
    String marker,
    Set<String> isolated,
  ) async {
    final ids = group.map((e) => e.operationId).toList();
    isolated.addAll(ids);
    await (db.update(db.outboxEntries)..where((r) => r.operationId.isIn(ids)))
        .write(OutboxEntriesCompanion(lastError: Value(marker)));
  }

  Duration? _scheduleRetry() {
    if (_disposed || _paused || client.auth.currentUser == null) return null;
    _retryTimer?.cancel();
    final delay = syncRetryDelay(_consecutiveFailures++);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed && !_paused) unawaited(sync());
    });
    return delay;
  }

  Future<void> _syncProjects(SyncOverview? overview) async {
    for (final table in ['projects', 'project_sections']) {
      if (overview != null && await overview.matches(db, table, _requests)) {
        continue;
      }
      await for (final page in remotePages(client, table, scope: _requests)) {
        await mergeRemoteBatch(db, table, page, _requests);
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
      for (var start = 0; start < ids.length; start += idBatchSize) {
        final batch = ids.skip(start).take(idBatchSize).toList();
        for (final raw in await _requests.send(
          client.from(group.key).select().inFilter('id', batch),
        )) {
          await _mergeProject(group.key, raw);
        }
      }
    }
  }

  Future<void> _mergeProject(String table, Map<String, dynamic> raw) async {
    await mergeRemoteBatch(db, table, [raw], _requests);
  }

  /// Older servers remain usable, but cannot perform the new safe purge.
  Future<void> _pullPurgedEntities() async {
    try {
      await for (final page in remotePages(
        client,
        'purged_entities',
        scope: _requests,
      )) {
        await mergePurgeBatch(db, page, _requests);
      }
    } on PostgrestException catch (e) {
      if (!const {'42P01', 'PGRST205'}.contains(e.code)) rethrow;
    }
  }

  Future<bool> _reconcileRecurringOccurrence(Task local) async {
    final seriesId = local.seriesId;
    final occurrenceKey = local.occurrenceKey;
    if (seriesId == null || occurrenceKey == null) return false;

    final rows = await _requests.send(
      client
          .from('tasks')
          .select()
          .eq('series_id', seriesId)
          .eq('occurrence_key', occurrenceKey)
          .limit(1),
    );
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

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _syncAgain = false;
    _cancelRequests();
    _timer?.cancel();
    _outboxTimer?.cancel();
    _realtimeTimer?.cancel();
    _retryTimer?.cancel();
    await _connection.dispose();
    await _outbox?.cancel();
    await _removeRealtime();
    await Future.wait(_operations.toList());
    await _state.close();
    await _remoteTaskChanges.close();
  }
}
