import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/run_tracker_service.dart';

/// Compact detail opened from the step ring; replaces the archived Movimento tab.
Future<void> showDailyStepsSheet(
  BuildContext context, {
  required DailyMovementProgress? progress,
  required int goal,
  required Future<void> Function() enableSteps,
  required VoidCallback editGoal,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => DailyStepsSheet(
    progress: progress,
    goal: goal,
    enableSteps: enableSteps,
    editGoal: editGoal,
  ),
);

class DailyStepsSheet extends StatelessWidget {
  const DailyStepsSheet({
    required this.progress,
    required this.goal,
    required this.enableSteps,
    required this.editGoal,
    super.key,
  });

  final DailyMovementProgress? progress;
  final int goal;
  final Future<void> Function() enableSteps;
  final VoidCallback editGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = progress?.steps ?? 0;
    final ratio = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Passi di oggi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${formatSteps(steps)} / ${formatSteps(goal)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Text(
              stepCollectionLabel(progress, DateTime.now()),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // Wrap, not Row: large accessibility fonts must not overflow.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                if (progress?.collectionStatus == 'permission_required')
                  FilledButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await enableSteps();
                    },
                    child: const Text('Abilita conteggio passi'),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    editGoal();
                  },
                  child: const Text('Cambia obiettivo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatSteps(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);

String stepCollectionLabel(DailyMovementProgress? daily, DateTime now) {
  final status = daily?.collectionStatus ?? 'not_started';
  return switch (status) {
    'permission_required' => 'Consenti Attività fisica per contare i passi.',
    'subscribed_no_samples' => 'Raccolta attiva · dati non ancora disponibili.',
    'awaiting_complete_minute' =>
      'Conteggio attivato · in attesa del primo minuto.',
    'subscribing' || 'reading' || 'not_started' => 'Aggiornamento dei passi…',
    'subscribed' when daily?.coverage == 'retention_gap' =>
      'Conteggio attivo · alcuni intervalli non recuperabili.',
    'subscribed'
        when daily?.lastImport != null &&
            now.difference(daily!.lastImport!) > const Duration(hours: 6) =>
      'Ultimo aggiornamento dei passi in ritardo.',
    'subscribed' => 'Passi in background · aggiornati al minuto completo.',
    _ =>
      'Conteggio non disponibile · dati salvati conservati. '
          'Controlla permessi e Play Services.',
  };
}

/// Returns the requested goal; Android normalizes it to 1.000–100.000.
Future<int?> showStepGoalDialog(BuildContext context, int current) async {
  final controller = TextEditingController(text: '$current');
  final value = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Obiettivo passi giornaliero'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Passi',
          helperText: 'Da 1.000 a 100.000',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = int.tryParse(controller.text);
            if (parsed != null) Navigator.pop(dialogContext, parsed);
          },
          child: const Text('Salva'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}
