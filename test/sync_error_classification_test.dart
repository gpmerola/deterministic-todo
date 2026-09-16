import 'dart:async';

import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Simulates dart2js release names: the string carries no transport information.
class _OpaqueClientError extends http.ClientException {
  _OpaqueClientError() : super('Synthetic private URL and response');
  @override
  Type get runtimeType => Object;
}

class _OpaqueTimeout extends TimeoutException {
  _OpaqueTimeout() : super('Synthetic private request');
  @override
  Type get runtimeType => Object;
}

void main() {
  test('transport recovery is independent of minified runtime type names', () {
    for (final (error, category, type) in [
      (_OpaqueClientError(), 'network', 'ClientException'),
      (_OpaqueTimeout(), 'timeout', 'TimeoutException'),
      (
        AuthRetryableFetchException(message: 'Synthetic private response'),
        'auth_transport',
        'AuthRetryableFetchException',
      ),
    ]) {
      expect(safeSyncErrorClass(error), category);
      expect(isTransientSyncError(error), isTrue);
      expect(safeSyncErrorType(error), type);
      expect(safeSyncErrorCode(error), 'Rete $type');
      expect(safeSyncErrorCode(error), isNot(contains('private')));
    }
  });
}
