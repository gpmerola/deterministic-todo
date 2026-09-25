import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' show LogicalVersion;
import '../../services/diagnostic_log_service.dart';
import '../local/database.dart';
import 'paged_remote.dart';
import 'project_sync_writer.dart';
import 'purge_batch_merge.dart';
import 'remote_batch_merge.dart';
import 'sync_overview.dart';
import 'sync_request_scope.dart';
import 'task_fingerprints.dart';
import 'task_sync_writer.dart';

enum SyncPhase { disabled, offline, syncing, current, error }

enum SyncStage {
  idle,
  overview,
  projects,
  taskUpload,
  receipt,
  taskPull,
  taskMerge,
  purgePull,
}

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

  /// Keeps `id=in.(...)` URLs well below common proxy limits.
  static const idBatchSize = 100;
  static const receiptBatchSize = 200;
  final AppDatabase db;
  final SupabaseClient client;
  final _state = StreamController<SyncSnapshot>.broadcast();
  final _remoteTaskChanges = StreamController<Set<String>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<Set<String>>? _outbox;
  RealtimeChannel? _realtime;
  Timer? _timer;
  Timer? _outboxTimer;
  Timer? _realtimeTimer;
  Timer? _realtimeReconnectTimer;
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
    _latest = snapshot;
    _state.add(snapshot);
  }

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _authenticatedUserId = client.auth.currentUser?.id;
    _auth = client.auth.onAuthStateChange.listen((state) {
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
    });
    _outbox = db.watchOutboxOperationIds().listen((operations) {
      final hasNewWork = outboxOperationsChanged(
        _observedOutboxOperations,
        operations,
      );
      _observedOutboxOperations = operations;
      if (operations.isNotEmpty && hasNewWork) _scheduleOutboxSync();
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
      } else if (!_paused) {
        // In background the next resume performs the check.
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
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
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

  Future<void> _subscribeRealtime() async {
    if (_disposed) return;
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
    if (_disposed || !identical(_realtime, channel)) return;
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
      // Events before this point were never delivered: the check must read
      // the server after the subscription, not join an older snapshot.
      if (!_disposed && !_paused) unawaited(sync(freshSnapshot: true));
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
    if (_disposed || _paused || client.auth.currentUser == null) return;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = Timer(const Duration(seconds: 2), () {
      _realtimeReconnectTimer = null;
      if (!_disposed && !_paused) unawaited(_subscribeRealtime());
    });
  }

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

  Future<void> _removeRealtime() async {
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    final channel = _realtime;
    _realtime = null;
    if (channel != null) await client.removeChannel(channel);
  }

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
        stage = SyncStage.projects;
        _reportProgress(cycle, stage, entries.length);
        await _syncProjects(overview);
        stage = SyncStage.taskPull;
        _reportProgress(cycle, stage, entries.length);
        final buckets = await changedTaskBuckets(
          db,
          client,
          _requests,
          fingerprints: overview?.tasks,
        );
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
        if (overview != null && buckets != null) {
          divergedBuckets = await unresolvedTaskBuckets(
            db,
            overview.tasks,
            buckets,
            _requests,
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
    _realtimeReconnectTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivity?.cancel();
    await _auth?.cancel();
    await _outbox?.cancel();
    await _removeRealtime();
    await Future.wait(_operations.toList());
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
  if (error is SyncPaginationException) return 'pagination';
  if (error is SyncIntentConflictException) return 'intent_conflict';
  if (error is SyncConcurrentWriteException) return 'concurrent_write';
  if (error is SyncWriteVerificationException) return 'write_verification';
  if (error is PostgrestException) return 'supabase';
  if (error is AuthRetryableFetchException) return 'auth_transport';
  if (error is TimeoutException) return 'timeout';
  if (error is http.ClientException) return 'network';
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

LogicalVersion? announcedVersion(Map<String, dynamic> record) {
  final counter = record['logical_version'];
  final device = record['device_id'];
  return counter is int && device is String
      ? LogicalVersion(counter, device)
      : null;
}

/// Drops notifications whose announced version this device already has,
/// such as the echo of its own accepted upload. Anything uncertain is fetched.
Future<Set<String>> realtimeIdsToFetch(
  AppDatabase db,
  String table,
  Set<String> ids,
  Map<String, LogicalVersion?> announced,
) async {
  if (!const {'tasks', 'projects', 'project_sections'}.contains(table)) {
    throw ArgumentError('Invalid sync table');
  }
  final known = ids.where((id) => announced[id] != null).toList();
  if (known.isEmpty) return ids;
  final rows = await db
      .customSelect(
        'SELECT id, logical_version, device_id FROM "$table" '
        'WHERE id IN (SELECT value FROM json_each(?))',
        variables: [Variable(jsonEncode(known))],
      )
      .get();
  final current = {
    for (final row in rows)
      row.read<String>('id'): LogicalVersion(
        row.read<int>('logical_version'),
        row.read<String>('device_id'),
      ),
  };
  return {
    for (final id in ids)
      if (announced[id] == null ||
          current[id] == null ||
          current[id]!.compareTo(announced[id]!) < 0)
        id,
  };
}

bool outboxOperationsChanged(Set<String> previous, Set<String> current) =>
    previous.length != current.length || !previous.containsAll(current);

/// SQLSTATE classes 22 (data) and 23 (integrity) concern the submitted row.
/// Auth, RLS, schema and transport errors still abort the whole cycle.
bool isEntityRejection(PostgrestException error) {
  final code = error.code;
  return code != null &&
      code.length == 5 &&
      (code.startsWith('22') || code.startsWith('23'));
}

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
  if (error is http.ClientException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return true;
  }
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
  if (error is SyncPaginationException) {
    return 'Allineamento incompleto: ordine dei dati ricevuti non valido';
  }
  if (error is SyncIntentConflictException) {
    return 'Conflitto: scegli la versione nello storico attività';
  }
  if (error is PostgrestException) return 'Supabase ${error.code}';
  final type = safeSyncErrorType(error);
  if (isTransientSyncError(error)) return 'Rete $type';
  return type;
}

/// Known transport types remain stable in minified Web releases. Never include
/// exception messages, which can contain URLs, credentials or response content.
String safeSyncErrorType(Object error) {
  if (error is http.ClientException) return 'ClientException';
  if (error is TimeoutException) return 'TimeoutException';
  if (error is AuthRetryableFetchException) {
    return 'AuthRetryableFetchException';
  }
  if (error is SyncPaginationException) return 'SyncPaginationException';
  if (error is PostgrestException) return 'PostgrestException';
  return error.runtimeType.toString();
}
