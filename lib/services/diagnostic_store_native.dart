import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'diagnostic_store.dart';

Future<DiagnosticStore> createDiagnosticStore({required int maxBytes}) async {
  final directory = await getApplicationSupportDirectory();
  return _FileDiagnosticStore(
    File('${directory.path}/diagnostics.jsonl'),
    maxBytes,
  );
}

class _FileDiagnosticStore implements DiagnosticStore {
  _FileDiagnosticStore(this.file, this.maxBytes);

  final File file;
  final int maxBytes;

  @override
  Future<void> append(String line) async {
    if (await file.exists() && await file.length() >= maxBytes) {
      final previous = File('${file.path}.1');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  @override
  Future<Uint8List> read() async => await file.exists()
      ? file.readAsBytes()
      : Uint8List.fromList(utf8.encode(''));
}
