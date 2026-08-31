import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openDatabaseConnection() => DatabaseConnection.delayed(
  Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'deterministic_todo',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    if (result.chosenImplementation == WasmStorageImplementation.inMemory) {
      throw UnsupportedError(
        'Il browser non offre uno storage locale persistente. '
        'Apri l’app in una versione recente di Chrome o Edge.',
      );
    }
    return result.resolvedExecutor;
  }),
);
