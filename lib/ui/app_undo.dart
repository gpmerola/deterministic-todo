part of '../main.dart';

/// Un solo punto per tutte le azioni reversibili dell'interfaccia.
abstract final class AppUndo {
  static void show(
    BuildContext context, {
    required String message,
    required Future<void> Function() undo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () => unawaited(undo()),
          ),
        ),
      );
  }
}
