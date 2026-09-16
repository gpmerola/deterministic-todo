part of '../main.dart';

/// Un solo punto per tutte le azioni reversibili dell'interfaccia.
abstract final class AppUndo {
  static void show(
    BuildContext context, {
    required String message,
    required Future<void> Function() undo,
    Duration duration = const Duration(seconds: 5),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          // Anche con servizi di accessibilità attivi l'annuncio non deve
          // diventare un elemento permanente dell'interfaccia.
          persist: false,
          showCloseIcon: true,
          content: Text(message),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () => unawaited(undo()),
          ),
        ),
      );
  }
}
