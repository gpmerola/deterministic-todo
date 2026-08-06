import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' as domain;
import '../../services/diagnostic_log_service.dart';
import '../local/database.dart';

enum SyncPhase { disabled, offline, syncing, current, error }

class SyncSnapshot {
  const SyncSnapshot(
    this.phase, {
    this.pending = 0,
    this.lastSuccess,
    this.error,
  });
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSuccess;
  final String? error;
}

class SyncService {
  SyncService(this.db, this.client);
  static const periodicInterval = Duration(minutes: 15);
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
  Timer? _retryTimer;
  Future<void>? _inFlight;
  bool _syncAgain = false;
  bool _pullAllRequested = false;
  bool _paused = false;
  int _consecutiveFailures = 0;
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
      if (entries.isNotEmpty) _scheduleOutboxSync();
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
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void resume() {
    _paused = false;
    _startTimer();
    unawaited(sync());
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
    if (user == null || _realtime != null) return;
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: user.id,
    );
    final channel = client.channel('todo-live-${user.id}');
    for (final table in const ['tasks', 'projects', 'project_sections']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: filter,
        callback: (payload) => _queueRealtimeChange(table, payload),
      );
    }
    _realtime = channel..subscribe();
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
      // Il controllo completo periodico recupera qualunque evento perso.
    }
  }

  Future<void> _removeRealtime() async {
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
    final entries = await (db.select(
      db.outboxEntries,
    )..orderBy([(row) => OrderingTerm(expression: row.createdAt)])).get();
    _emit(SyncSnapshot(SyncPhase.syncing, pending: entries.length));
    unawaited(
      DiagnosticLogService.instance.event(
        'sync_started',
        fields: {'pending': entries.length},
      ),
    );
    final timer = Stopwatch()..start();
    try {
      final projectMetrics = pullAll
          ? await _syncProjects()
          : (skippedProjects: 0, skippedSections: 0);
      final acknowledged = <OutboxEntry>[...entries];
      final pendingIds = distinctEntityIds(
        entries.map((entry) => entry.entityId),
      );
      var uploadedEntities = 0;
      if (pendingIds.isNotEmpty) {
        final pendingTasks = await (db.select(
          db.tasks,
        )..where((row) => row.id.isIn(pendingIds))).get();
        for (final task in pendingTasks) {
          await client.rpc('merge_task', params: {'record': _remoteTask(task)});
        }
        uploadedEntities = pendingTasks.length;
      }
      if (acknowledged.isNotEmpty) {
        await client.from('sync_operations').upsert([
          for (final entry in acknowledged)
            {
              'operation_id': entry.operationId,
              'entity_id': entry.entityId,
              'operation': entry.operation,
              'payload': jsonDecode(entry.payload) as Map<String, Object?>,
            },
        ], onConflict: 'operation_id');
        await db.transaction(() async {
          for (final entry in acknowledged) {
            await (db.delete(
              db.outboxEntries,
            )..where((row) => row.operationId.equals(entry.operationId))).go();
          }
        });
      }
      final remoteRows = pullAll
          ? await client.from('tasks').select()
          : const <Map<String, dynamic>>[];
      final remoteIds = remoteRows
          .map((raw) => raw['id'] as String)
          .toList(growable: false);
      final localTasks = remoteIds.isEmpty
          ? const <Task>[]
          : await (db.select(
              db.tasks,
            )..where((row) => row.id.isIn(remoteIds))).get();
      final localById = {for (final task in localTasks) task.id: task};
      for (final raw in remoteRows) {
        await _mergeRemote(raw, localById[raw['id'] as String]);
      }
      final now = DateTime.now().toUtc();
      timer.stop();
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      _emit(SyncSnapshot(SyncPhase.current, lastSuccess: now));
      unawaited(
        DiagnosticLogService.instance.event(
          'sync_completed',
          fields: {
            'count': entries.length,
            'uploaded_entities': uploadedEntities,
            'remote_rows': remoteRows.length,
            'skipped_projects': projectMetrics.skippedProjects,
            'skipped_sections': projectMetrics.skippedSections,
            'duration_ms': timer.elapsedMilliseconds,
          },
        ),
      );
    } catch (error) {
      timer.stop();
      final errorCode = safeSyncErrorCode(error);
      _emit(
        SyncSnapshot(
          SyncPhase.error,
          pending: entries.length,
          error: errorCode,
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
            'error_type': error.runtimeType.toString(),
            if (error is PostgrestException) 'error_code': error.code,
            'duration_ms': timer.elapsedMilliseconds,
          },
        ),
      );
      if (isTransientSyncError(error)) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_paused || client.auth.currentUser == null) return;
    _retryTimer?.cancel();
    final delay = syncRetryDelay(_consecutiveFailures++);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_paused) unawaited(sync());
    });
  }

  Future<({int skippedProjects, int skippedSections})> _syncProjects() async {
    var skippedProjects = 0;
    var skippedSections = 0;
    final savedRows =
        await (db.select(db.appSettings)..where(
              (row) =>
                  row.key.like('sync_project:%') |
                  row.key.like('sync_section:%'),
            ))
            .get();
    final savedFingerprints = {
      for (final setting in savedRows) setting.key: setting.value,
    };
    final projects = await db.select(db.projects).get();
    for (final project in projects) {
      final fingerprint = _fingerprint(
        project.logicalVersion,
        project.deviceId,
      );
      if (savedFingerprints['sync_project:${project.id}'] == fingerprint) {
        skippedProjects++;
        continue;
      }
      await client.rpc(
        'merge_project',
        params: {'record': _remoteProject(project)},
      );
      await _saveSyncedFingerprint('project', project.id, fingerprint);
    }
    final sections = await db.select(db.projectSections).get();
    for (final section in sections) {
      final fingerprint = _fingerprint(
        section.logicalVersion,
        section.deviceId,
      );
      if (savedFingerprints['sync_section:${section.id}'] == fingerprint) {
        skippedSections++;
        continue;
      }
      await client.rpc(
        'merge_project_section',
        params: {'record': _remoteSection(section)},
      );
      await _saveSyncedFingerprint('section', section.id, fingerprint);
    }
    for (final raw in await client.from('projects').select()) {
      final local = await (db.select(
        db.projects,
      )..where((row) => row.id.equals(raw['id'] as String))).getSingleOrNull();
      final remoteVersion = domain.LogicalVersion(
        raw['logical_version'] as int,
        raw['device_id'] as String,
      );
      if (local != null &&
          remoteVersion.compareTo(
                domain.LogicalVersion(local.logicalVersion, local.deviceId),
              ) <=
              0) {
        continue;
      }
      await db
          .into(db.projects)
          .insertOnConflictUpdate(
            ProjectsCompanion(
              id: Value(raw['id'] as String),
              userId: Value(raw['user_id'] as String?),
              name: Value(raw['name'] as String),
              color: Value(raw['color'] as String?),
              parentId: Value(raw['parent_id'] as String?),
              position: Value(raw['position'] as int),
              isFavorite: Value(raw['is_favorite'] as bool),
              isArchived: Value(raw['is_archived'] as bool),
              externalSource: Value(raw['external_source'] as String?),
              externalId: Value(raw['external_id'] as String?),
              logicalVersion: Value(raw['logical_version'] as int),
              deviceId: Value(raw['device_id'] as String),
            ),
          );
      await _saveSyncedFingerprint(
        'project',
        raw['id'] as String,
        _fingerprint(raw['logical_version'] as int, raw['device_id'] as String),
      );
    }
    for (final raw in await client.from('project_sections').select()) {
      final local = await (db.select(
        db.projectSections,
      )..where((row) => row.id.equals(raw['id'] as String))).getSingleOrNull();
      final remoteVersion = domain.LogicalVersion(
        raw['logical_version'] as int,
        raw['device_id'] as String,
      );
      if (local != null &&
          remoteVersion.compareTo(
                domain.LogicalVersion(local.logicalVersion, local.deviceId),
              ) <=
              0) {
        continue;
      }
      await db
          .into(db.projectSections)
          .insertOnConflictUpdate(
            ProjectSectionsCompanion(
              id: Value(raw['id'] as String),
              userId: Value(raw['user_id'] as String?),
              projectId: Value(raw['project_id'] as String),
              name: Value(raw['name'] as String),
              position: Value(raw['position'] as int),
              isArchived: Value(raw['is_archived'] as bool),
              externalSource: Value(raw['external_source'] as String?),
              externalId: Value(raw['external_id'] as String?),
              logicalVersion: Value(raw['logical_version'] as int),
              deviceId: Value(raw['device_id'] as String),
            ),
          );
      await _saveSyncedFingerprint(
        'section',
        raw['id'] as String,
        _fingerprint(raw['logical_version'] as int, raw['device_id'] as String),
      );
    }
    return (skippedProjects: skippedProjects, skippedSections: skippedSections);
  }

  Future<void> _pullRemoteProjects({
    required Set<String> projectIds,
    required Set<String> sectionIds,
  }) async {
    if (projectIds.isNotEmpty) {
      for (final raw
          in await client
              .from('projects')
              .select()
              .inFilter('id', projectIds.toList())) {
        final local =
            await (db.select(db.projects)
                  ..where((row) => row.id.equals(raw['id'] as String)))
                .getSingleOrNull();
        final remoteVersion = domain.LogicalVersion(
          raw['logical_version'] as int,
          raw['device_id'] as String,
        );
        if (local != null &&
            remoteVersion.compareTo(
                  domain.LogicalVersion(local.logicalVersion, local.deviceId),
                ) <=
                0) {
          continue;
        }
        await db
            .into(db.projects)
            .insertOnConflictUpdate(
              ProjectsCompanion(
                id: Value(raw['id'] as String),
                userId: Value(raw['user_id'] as String?),
                name: Value(raw['name'] as String),
                color: Value(raw['color'] as String?),
                parentId: Value(raw['parent_id'] as String?),
                position: Value(raw['position'] as int),
                isFavorite: Value(raw['is_favorite'] as bool),
                isArchived: Value(raw['is_archived'] as bool),
                externalSource: Value(raw['external_source'] as String?),
                externalId: Value(raw['external_id'] as String?),
                logicalVersion: Value(raw['logical_version'] as int),
                deviceId: Value(raw['device_id'] as String),
              ),
            );
      }
    }
    if (sectionIds.isNotEmpty) {
      for (final raw
          in await client
              .from('project_sections')
              .select()
              .inFilter('id', sectionIds.toList())) {
        final local =
            await (db.select(db.projectSections)
                  ..where((row) => row.id.equals(raw['id'] as String)))
                .getSingleOrNull();
        final remoteVersion = domain.LogicalVersion(
          raw['logical_version'] as int,
          raw['device_id'] as String,
        );
        if (local != null &&
            remoteVersion.compareTo(
                  domain.LogicalVersion(local.logicalVersion, local.deviceId),
                ) <=
                0) {
          continue;
        }
        await db
            .into(db.projectSections)
            .insertOnConflictUpdate(
              ProjectSectionsCompanion(
                id: Value(raw['id'] as String),
                userId: Value(raw['user_id'] as String?),
                projectId: Value(raw['project_id'] as String),
                name: Value(raw['name'] as String),
                position: Value(raw['position'] as int),
                isArchived: Value(raw['is_archived'] as bool),
                externalSource: Value(raw['external_source'] as String?),
                externalId: Value(raw['external_id'] as String?),
                logicalVersion: Value(raw['logical_version'] as int),
                deviceId: Value(raw['device_id'] as String),
              ),
            );
      }
    }
  }

  String _fingerprint(int version, String deviceId) => '$version:$deviceId';

  Future<void> _saveSyncedFingerprint(String type, String id, String value) =>
      db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: 'sync_$type:$id', value: value),
          );

  Future<bool> _mergeRemote(Map<String, dynamic> raw, Task? local) async {
    final id = raw['id'] as String;
    final remoteVersion = domain.LogicalVersion(
      raw['logical_version'] as int,
      raw['device_id'] as String,
    );
    if (local != null) {
      final localVersion = domain.LogicalVersion(
        local.logicalVersion,
        local.deviceId,
      );
      if (remoteVersion.compareTo(localVersion) <= 0) return false;
    }
    await db
        .into(db.tasks)
        .insertOnConflictUpdate(
          TasksCompanion(
            id: Value(id),
            userId: Value(raw['user_id'] as String?),
            title: Value(raw['title'] as String),
            notes: Value(raw['notes'] as String?),
            status: Value(raw['status'] as String),
            showDate: Value(raw['show_date'] as String?),
            // Legacy column retained in the remote schema for compatibility.
            // Planning now has a single canonical civil date: show_date.
            dueDate: const Value(null),
            timeMinutes: const Value(null),
            timeZone: const Value(null),
            priority: Value(raw['priority'] as int? ?? 1),
            projectId: Value(raw['project_id'] as String?),
            sectionId: Value(raw['section_id'] as String?),
            externalSource: Value(raw['external_source'] as String?),
            externalId: Value(raw['external_id'] as String?),
            position: Value(raw['position'] as int),
            recurrence: Value(raw['recurrence'] as String?),
            seriesId: Value(raw['series_id'] as String?),
            occurrenceKey: Value(raw['occurrence_key'] as String?),
            createdAt: Value(raw['created_at'] as int),
            updatedAt: Value(raw['updated_at'] as int),
            completedAt: Value(raw['completed_at'] as int?),
            deletedAt: Value(raw['deleted_at'] as int?),
            logicalVersion: Value(raw['logical_version'] as int),
            deviceId: Value(raw['device_id'] as String),
          ),
        );
    return true;
  }

  Map<String, Object?> _remoteTask(Task task) => {
    'id': task.id,
    'user_id': client.auth.currentUser!.id,
    'title': task.title,
    'notes': task.notes,
    'status': task.status,
    'show_date': task.showDate,
    'due_date': null,
    'time_minutes': null,
    'time_zone': null,
    'priority': task.priority,
    'project_id': task.projectId,
    'section_id': task.sectionId,
    'external_source': task.externalSource,
    'external_id': task.externalId,
    'position': task.position,
    'recurrence': task.recurrence,
    'series_id': task.seriesId,
    'occurrence_key': task.occurrenceKey,
    'created_at': task.createdAt,
    'updated_at': task.updatedAt,
    'completed_at': task.completedAt,
    'deleted_at': task.deletedAt,
    'logical_version': task.logicalVersion,
    'device_id': task.deviceId,
  };

  Map<String, Object?> _remoteProject(Project project) => {
    'id': project.id,
    'user_id': client.auth.currentUser!.id,
    'name': project.name,
    'color': project.color,
    'parent_id': project.parentId,
    'position': project.position,
    'is_favorite': project.isFavorite,
    'is_archived': project.isArchived,
    'external_source': project.externalSource,
    'external_id': project.externalId,
    'logical_version': project.logicalVersion,
    'device_id': project.deviceId,
  };

  Map<String, Object?> _remoteSection(ProjectSection section) => {
    'id': section.id,
    'user_id': client.auth.currentUser!.id,
    'project_id': section.projectId,
    'name': section.name,
    'position': section.position,
    'is_archived': section.isArchived,
    'external_source': section.externalSource,
    'external_id': section.externalId,
    'logical_version': section.logicalVersion,
    'device_id': section.deviceId,
  };

  Future<void> dispose() async {
    _timer?.cancel();
    _outboxTimer?.cancel();
    _realtimeTimer?.cancel();
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

bool isTransientSyncError(Object error) {
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
  if (error is PostgrestException) return 'Supabase ${error.code}';
  final type = error.runtimeType.toString();
  if (isTransientSyncError(error)) return 'Rete $type';
  return type;
}
