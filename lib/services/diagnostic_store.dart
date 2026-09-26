import 'dart:typed_data';

abstract interface class DiagnosticStore {
  Future<void> append(String line);
  Future<Uint8List> read();
}
