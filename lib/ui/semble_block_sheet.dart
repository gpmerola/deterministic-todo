import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../services/semble_service.dart';

/// Whether Settings hold everything a Semble block needs (build 297).
Future<bool> sembleBlockReady(SembleSettings settings) async {
  try {
    final config = await settings.read();
    return config.ready && config.roomId != null;
  } on Object {
    // No secure storage (web, tests): no block action.
    return false;
  }
}

/// Types shown at once in the block form; the rest sit under "Altri tipi"
/// (build 298).
const sembleQuickBlockTypes = [
  SembleBlockType.generalAdmin,
  SembleBlockType.annualLeave,
  SembleBlockType.sickness,
  SembleBlockType.other,
];

/// Last type used in this run of the app, preselected next time.
SembleBlockType lastSembleBlockType = SembleBlockType.generalAdmin;

/// Creates a Semble unavailability for [start]–[end] (build 298). Called
/// only from the explicit "Blocca in Semble" button; the snackbar offers to
/// delete exactly that block. Throws [SembleException] when Semble refuses,
/// so the form can show why.
Future<void> createSembleBlock(
  BuildContext context, {
  required DateTime start,
  required DateTime end,
  required SembleBlockType type,
  SembleSettings? settings,
  SembleClient? client,
  SembleLayer? layer,
}) async {
  final store = settings ?? SembleSettings();
  final semble = client ?? SembleClient();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final config = await store.read();
  final key = await store.apiKey();
  if (key == null || config.userId == null || config.roomId == null) {
    throw const SembleException(SembleFailure.noKey);
  }
  final created = await semble.createUnavailability(
    key: key,
    userId: config.userId!,
    roomId: config.roomId!,
    start: start,
    end: end,
    type: type,
  );
  lastSembleBlockType = type;
  final shared = layer ?? SembleLayer.shared;
  Future<void> refresh() => shared.refresh(
    today: CivilDate.fromDateTime(DateTime.now()),
    force: true,
  );
  // The new block appears as an unavailable band once Semble is read again.
  await refresh().catchError((Object _) {});
  messenger?.showSnackBar(
    SnackBar(
      content: const Text('Bloccato in Semble.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Annulla',
        onPressed: () async {
          try {
            await semble.deleteUnavailability(key: key, id: created);
            await refresh();
            messenger.showSnackBar(
              const SnackBar(content: Text('Blocco Semble annullato.')),
            );
          } on Object catch (error) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  error is SembleException
                      ? 'Blocco non annullato: ${error.message}'
                      : 'Blocco non annullato: toglilo da Semble.',
                ),
              ),
            );
          }
        },
      ),
    ),
  );
}
