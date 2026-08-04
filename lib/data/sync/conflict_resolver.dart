import '../../domain/task.dart';

T resolveConflict<T>({
  required T local,
  required LogicalVersion localVersion,
  required T remote,
  required LogicalVersion remoteVersion,
}) => remoteVersion.compareTo(localVersion) > 0 ? remote : local;
