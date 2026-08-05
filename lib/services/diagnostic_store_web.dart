import 'dart:convert';
import 'dart:typed_data';

import 'diagnostic_store.dart';

Future<DiagnosticStore> createDiagnosticStore({required int maxBytes}) async =>
    _MemoryDiagnosticStore(maxBytes);

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
