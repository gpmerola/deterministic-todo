import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'diagnostic_store.dart';

Future<DiagnosticStore> createDiagnosticStore({required int maxBytes}) async {
  final directory = await getApplicationSupportDirectory();
  return FileDiagnosticStore(
    File('${directory.path}/diagnostics.jsonl'),
    maxBytes,
  );
}

class FileDiagnosticStore implements DiagnosticStore {
  FileDiagnosticStore(this.file, this.maxBytes, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final File file;
  final int maxBytes;
  final DateTime Function() _now;

  static const retention = Duration(days: 7);

  String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<List<File>> _retainedFiles() async {
    final threshold = _now().subtract(retention);
    final entries = await file.parent
        .list()
        .where((entry) {
          return entry is File &&
              (entry.path.endsWith('/diagnostics.jsonl') ||
                  entry.path.endsWith('/diagnostics.jsonl.1') ||
                  RegExp(
                    r'/diagnostics-\d{4}-\d{2}-\d{2}(-\d+)?\.jsonl$',
                  ).hasMatch(entry.path));
        })
        .cast<File>()
        .toList();
    final retained = <File>[];
    for (final entry in entries) {
      final match = RegExp(
        r'diagnostics-(\d{4})-(\d{2})-(\d{2})(?:-\d+)?\.jsonl$',
      ).firstMatch(entry.path);
      final logicalDate = match == null
          ? await entry.lastModified()
          : DateTime(
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
              int.parse(match.group(3)!),
              23,
              59,
              59,
            );
      if (logicalDate.isBefore(threshold)) {
        await entry.delete(); // Local app-private retention only; never Drive.
      } else {
        retained.add(entry);
      }
    }
    retained.sort((a, b) {
      final modified = a.lastModifiedSync().compareTo(b.lastModifiedSync());
      return modified != 0 ? modified : a.path.compareTo(b.path);
    });
    return retained;
  }

  @override
  Future<void> append(String line) async {
    final prefix = '${file.parent.path}/diagnostics-${_day(_now())}';
    var segment = 0;
    var target = File('$prefix.jsonl');
    while (await target.exists() && await target.length() >= maxBytes) {
      segment++;
      target = File('$prefix-$segment.jsonl');
    }
    await target.writeAsString(line, mode: FileMode.append, flush: true);
    await _retainedFiles();
  }

  @override
  Future<Uint8List> read() async {
    final output = BytesBuilder(copy: false);
    for (final retained in await _retainedFiles()) {
      output.add(await retained.readAsBytes());
    }
    return output.takeBytes();
  }
}
