import 'package:flutter/material.dart';

/// A failed read must never look like an empty calendar. Keep the existing
/// page visible below the message, including when retrying a newer revision.
class AgendaPageFrame extends StatelessWidget {
  const AgendaPageFrame({
    required this.failed,
    required this.loading,
    required this.onRetry,
    required this.child,
    super.key,
  });
  final bool failed, loading;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (failed || loading)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  loading
                      ? 'Aggiornamento del calendario…'
                      : 'Calendario non aggiornato: lettura non riuscita.',
                ),
              ),
              TextButton(
                onPressed: loading ? null : onRetry,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      Expanded(child: child),
    ],
  );
}
