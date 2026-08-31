import 'dart:io';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('riprende una migrazione versione 2 rimasta a metà', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-db-migration-',
    );
    final file = File('${directory.path}/todo.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NULL,
        title TEXT NOT NULL,
        notes TEXT NULL,
        status TEXT NOT NULL,
        show_date TEXT NULL,
        due_date TEXT NULL,
        time_minutes INTEGER NULL,
        time_zone TEXT NULL,
        position INTEGER NOT NULL,
        recurrence TEXT NULL,
        series_id TEXT NULL,
        occurrence_key TEXT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER NULL,
        deleted_at INTEGER NULL,
        logical_version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        UNIQUE (series_id, occurrence_key)
      )
    ''');
    legacy.execute('''
      CREATE TABLE outbox_entries (
        operation_id TEXT NOT NULL PRIMARY KEY,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NULL
      )
    ''');
    legacy.execute('''
      CREATE TABLE app_settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    legacy.execute('PRAGMA user_version = 2');
    legacy.execute(
      'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1',
    );
    legacy.execute('ALTER TABLE tasks ADD COLUMN project_id TEXT NULL');
    legacy.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(await database.select(database.tasks).get(), isEmpty);
    expect(await database.select(database.projects).get(), isEmpty);
    expect(await database.select(database.projectSections).get(), isEmpty);
    final version = await database
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    expect(version, 6);
    final columns = await database
        .customSelect('PRAGMA table_info(tasks)')
        .get();
    expect(
      columns.any((row) => row.read<String>('name') == 'item_kind'),
      isTrue,
    );
    final indexes = await database
        .customSelect("PRAGMA index_list('tasks')")
        .get();
    expect(
      indexes.any((row) => row.read<String>('name') == 'tasks_kind_order_idx'),
      isFalse,
    );
  });

  test('rimuove l indice riferimenti da un database versione 5', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-db-v5-migration-',
    );
    final file = File('${directory.path}/todo.sqlite');
    final initial = AppDatabase.forTesting(NativeDatabase(file));
    await initial.select(initial.tasks).get();
    await initial.close();

    final versionFive = sqlite.sqlite3.open(file.path);
    versionFive.execute(
      'CREATE INDEX tasks_kind_order_idx '
      'ON tasks (item_kind, deleted_at, position, created_at, id)',
    );
    versionFive.execute('PRAGMA user_version = 5');
    versionFive.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async {
      await upgraded.close();
      await directory.delete(recursive: true);
    });
    await upgraded.select(upgraded.tasks).get();
    final indexes = await upgraded
        .customSelect("PRAGMA index_list('tasks')")
        .get();
    expect(
      indexes.any((row) => row.read<String>('name') == 'tasks_kind_order_idx'),
      isFalse,
    );
  });
}
