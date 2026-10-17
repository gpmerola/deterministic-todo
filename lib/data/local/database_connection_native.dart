import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openDatabaseConnection() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(p.join(directory.path, 'deterministic_todo.sqlite'));
  return NativeDatabase.createInBackground(file);
});
