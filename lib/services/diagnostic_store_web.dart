import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_shim.dart' as idb;

import 'diagnostic_store.dart';

Future<DiagnosticStore> createDiagnosticStore({required int maxBytes}) async {
  if (!idb.idbFactoryWebSupported) return _MemoryDiagnosticStore(maxBytes);
  final database = await idb.idbFactoryWeb.open(
    'deterministic_todo_diagnostics',
    version: 1,
    onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('logs')) {
        db.createObjectStore('logs');
      }
    },
  );
  return IndexedDbDiagnosticStore(database, maxBytes);
}

class IndexedDbDiagnosticStore implements DiagnosticStore {
  IndexedDbDiagnosticStore(this.database, this.maxBytes);

  final idb.Database database;
  final int maxBytes;

  Future<String> _get(String key) async {
    final transaction = database.transaction('logs', idb.idbModeReadOnly);
    final value = await transaction.objectStore('logs').getObject(key);
    await transaction.completed;
    return value as String? ?? '';
  }

  Future<void> _put(String key, String value) async {
    final transaction = database.transaction('logs', idb.idbModeReadWrite);
    await transaction.objectStore('logs').put(value, key);
    await transaction.completed;
  }

  @override
  Future<void> append(String line) async {
    var current = await _get('current');
    if (utf8.encode(current).length + utf8.encode(line).length > maxBytes) {
      await _put('previous', current);
      current = '';
    }
    await _put('current', '$current$line');
  }

  @override
  Future<Uint8List> read() async {
    final previous = await _get('previous');
    final current = await _get('current');
    return Uint8List.fromList(utf8.encode('$previous$current'));
  }
}

class _MemoryDiagnosticStore implements DiagnosticStore {
  _MemoryDiagnosticStore(this.maxBytes);

  final int maxBytes;
  final StringBuffer _buffer = StringBuffer();

  @override
  Future<void> append(String line) async {
    if (_buffer.length + line.length > maxBytes) _buffer.clear();
    _buffer.write(line);
  }

  @override
  Future<Uint8List> read() async =>
      Uint8List.fromList(utf8.encode(_buffer.toString()));
}
