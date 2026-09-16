import 'package:drift/drift.dart';

/// Drift 2.34.3's IndexedDB delegate skips flush while isInTransaction is true,
/// including COMMIT. A custom statement outside the completed transaction awaits
/// its existing VFS flush. Keep this adapter confined to Web, with no timers.
class WebTransactionFlush extends QueryInterceptor {
  final _parents = Expando<QueryExecutor>();

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final transaction = parent.beginTransaction();
    _parents[transaction] = parent;
    return transaction;
  }

  Future<void> _flush(TransactionExecutor transaction) async {
    final parent = _parents[transaction];
    // SAVEPOINT release is not a commit of the outer transaction.
    if (parent != null && parent is! TransactionExecutor) {
      // runSelect would skip _WasmDelegate._runWithArgs and its flush.
      await parent.runCustom('SELECT 1', const []);
    }
    _parents[transaction] = null;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    await _flush(inner);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    await _flush(inner);
  }
}
