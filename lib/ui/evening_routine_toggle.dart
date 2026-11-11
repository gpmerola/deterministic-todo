import 'package:flutter/material.dart';

import '../data/local/database.dart';
import '../services/evening_routine.dart';

/// Like the Calendar visibility control, saves immediately on an explicit tap.
class EveningRoutineToggle extends StatefulWidget {
  const EveningRoutineToggle({required this.db, required this.task, super.key});

  final AppDatabase db;
  final Task task;

  @override
  State<EveningRoutineToggle> createState() => _EveningRoutineToggleState();
}

class _EveningRoutineToggleState extends State<EveningRoutineToggle> {
  late Stream<Set<String>> flags = EveningRoutine(widget.db).watch();
  bool saving = false;

  @override
  void didUpdateWidget(covariant EveningRoutineToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) flags = EveningRoutine(widget.db).watch();
  }

  Future<void> _change(bool? value) async {
    if (value == null || saving) return;
    setState(() => saving = true);
    try {
      await EveningRoutine(widget.db).setEnabled(widget.task, value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine serale non salvata. Riprova.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: flags,
    builder: (context, snapshot) => CheckboxListTile(
      key: const ValueKey('task-evening-routine'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Routine serale'),
      subtitle: Text(
        snapshot.hasError
            ? 'Impossibile leggere la preferenza'
            : 'Salvata subito su questo dispositivo, anche per le ripetizioni',
      ),
      value:
          snapshot.data?.contains(EveningRoutine.identity(widget.task)) ??
          false,
      onChanged: saving || !snapshot.hasData || snapshot.hasError
          ? null
          : _change,
    ),
  );
}
