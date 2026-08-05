import 'dart:convert';
import 'dart:io';

import 'package:deterministic_todo/services/diagnostic_store_native.dart';
import 'package:deterministic_todo/services/diagnostic_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';

void main() {
  test('l export diagnostico include anche il file ruotato', () async {
    final directory = await Directory.systemTemp.createTemp('todo-log-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileDiagnosticStore(
      File('${directory.path}/diagnostics.jsonl'),
      12,
    );

    await store.append('prima-riga\n');
    await store.append('seconda-riga\n');

    expect(utf8.decode(await store.read()), 'prima-riga\nseconda-riga\n');
  });

  test('il log browser sopravvive alla riapertura dello store', () async {
    final database = await idbFactoryMemory.open(
      'diagnostics-test',
      version: 1,
      onUpgradeNeeded: (event) => event.database.createObjectStore('logs'),
    );
    final first = IndexedDbDiagnosticStore(database, 64);
    await first.append('evento\n');

    final reopened = IndexedDbDiagnosticStore(database, 64);
    expect(utf8.decode(await reopened.read()), 'evento\n');
    database.close();
  });
}
