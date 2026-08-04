import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/task.dart' as domain;
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
  final AppDatabase db;
  final SupabaseClient client;
  final _state = StreamController<SyncSnapshot>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  Future<void>? _inFlight;
  SyncSnapshot _latest = const SyncSnapshot(SyncPhase.disabled);

  Stream<SyncSnapshot> get snapshots => _state.stream;
  SyncSnapshot get latest => _latest;

  void _emit(SyncSnapshot snapshot) {
    _latest = snapshot;
    _state.add(snapshot);
  }

  void start() {
    _auth = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        unawaited(sync());
      } else {
        _emit(const SyncSnapshot(SyncPhase.disabled));
      }
    });
    _connectivity = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) unawaited(sync());
    });
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(sync()),
    );
    unawaited(sync());
  }

  Future<void> sync() {
    final active = _inFlight;
    if (active != null) return active;
    final operation = _syncOnce();
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<void> _syncOnce() async {
    if (client.auth.currentUser == null) {
      _emit(const SyncSnapshot(SyncPhase.disabled));
      return;
    }
    final entries = await (db.select(
      db.outboxEntries,
    )..orderBy([(row) => OrderingTerm(expression: row.createdAt)])).get();
    _emit(SyncSnapshot(SyncPhase.syncing, pending: entries.length));
    try {
      await _syncProjects();
      for (final entry in entries) {
        final payload = jsonDecode(entry.payload) as Map<String, Object?>;
        final task = await (db.select(
          db.tasks,
        )..where((row) => row.id.equals(entry.entityId))).getSingleOrNull();
        if (task != null) {
          await client.rpc('merge_task', params: {'record': _remoteTask(task)});
        }
        await client.from('sync_operations').upsert({
          'operation_id': entry.operationId,
          'entity_id': entry.entityId,
          'operation': entry.operation,
          'payload': payload,
        }, onConflict: 'operation_id');
        await (db.delete(
          db.outboxEntries,
        )..where((row) => row.operationId.equals(entry.operationId))).go();
      }
      final remoteRows = await client.from('tasks').select();
      for (final raw in remoteRows) {
        await _mergeRemote(raw);
      }
      final now = DateTime.now().toUtc();
      _emit(SyncSnapshot(SyncPhase.current, lastSuccess: now));
    } catch (error) {
      _emit(
        SyncSnapshot(
          SyncPhase.error,
          pending: entries.length,
          error: error.runtimeType.toString(),
        ),
      );
    }
  }

  Future<void> _syncProjects() async {
    final projects = await db.select(db.projects).get();
    for (final project in projects) {
      await client.rpc(
        'merge_project',
        params: {'record': _remoteProject(project)},
      );
    }
    final sections = await db.select(db.projectSections).get();
    for (final section in sections) {
      await client.rpc(
        'merge_project_section',
        params: {'record': _remoteSection(section)},
      );
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
    }
  }

  Future<void> _mergeRemote(Map<String, dynamic> raw) async {
    final id = raw['id'] as String;
    final local = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final remoteVersion = domain.LogicalVersion(
      raw['logical_version'] as int,
      raw['device_id'] as String,
    );
    if (local != null) {
      final localVersion = domain.LogicalVersion(
        local.logicalVersion,
        local.deviceId,
      );
      if (remoteVersion.compareTo(localVersion) <= 0) return;
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
            dueDate: Value(raw['due_date'] as String?),
            timeMinutes: Value(raw['time_minutes'] as int?),
            timeZone: Value(raw['time_zone'] as String?),
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
  }

  Map<String, Object?> _remoteTask(Task task) => {
    'id': task.id,
    'user_id': client.auth.currentUser!.id,
    'title': task.title,
    'notes': task.notes,
    'status': task.status,
    'show_date': task.showDate,
    'due_date': task.dueDate,
    'time_minutes': task.timeMinutes,
    'time_zone': task.timeZone,
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
    await _connectivity?.cancel();
    await _auth?.cancel();
    await _state.close();
  }
}
