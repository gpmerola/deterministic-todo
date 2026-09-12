import 'package:deterministic_todo/data/local/web_transaction_flush.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

class _Executor implements QueryExecutor {
  final events = <String>[];
  bool failFlush = false;
  @override
  TransactionExecutor beginTransaction() => _Transaction(this);
  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {
    events.add('flush:$statement');
    if (failFlush) throw StateError('Synthetic storage failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transaction implements TransactionExecutor {
  _Transaction(this.root);
  final _Executor root;
  @override
  TransactionExecutor beginTransaction() => _Transaction(root);
  @override
  Future<void> send() async {
    root.events.add('commit');
  }

  @override
  Future<void> rollback() async {
    root.events.add('rollback');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('il commit esterno attende il flush tramite runCustom', () async {
    final root = _Executor();
    final interceptor = WebTransactionFlush();
    final transaction = interceptor.beginTransaction(root);
    await interceptor.commitTransaction(transaction);
    expect(root.events, ['commit', 'flush:SELECT 1']);
  });
  test(
    'una transazione annidata non esegue flush prima del commit esterno',
    () async {
      final root = _Executor();
      final interceptor = WebTransactionFlush();
      final outer = interceptor.beginTransaction(root);
      final inner = interceptor.beginTransaction(outer);
      await interceptor.commitTransaction(inner);
      expect(root.events, ['commit']);
      await interceptor.commitTransaction(outer);
      expect(root.events, ['commit', 'commit', 'flush:SELECT 1']);
    },
  );
  test('rollback persiste lo stato ripristinato', () async {
    final root = _Executor();
    final interceptor = WebTransactionFlush();
    await interceptor.rollbackTransaction(interceptor.beginTransaction(root));
    expect(root.events, ['rollback', 'flush:SELECT 1']);
  });
  test(
    'un errore di persistenza non viene dichiarato un salvataggio riuscito',
    () async {
      final root = _Executor()..failFlush = true;
      final interceptor = WebTransactionFlush();
      await expectLater(
        interceptor.commitTransaction(interceptor.beginTransaction(root)),
        throwsStateError,
      );
    },
  );
}
