import 'package:flutter/material.dart';

import '../../services/agenda_reminders.dart';

class AgendaReminderSheet extends StatefulWidget {
  const AgendaReminderSheet({required this.reminders, super.key});
  final AgendaReminders reminders;

  @override
  State<AgendaReminderSheet> createState() => _AgendaReminderSheetState();
}

class _AgendaReminderSheetState extends State<AgendaReminderSheet>
    with WidgetsBindingObserver {
  bool? enabled;
  Map<Object?, Object?> status = {};
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final on = await widget.reminders.enabled();
      final current = await widget.reminders.status();
      if (mounted) {
        setState(() {
          enabled = on;
          status = current;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossibile leggere lo stato dei promemoria.');
      }
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.reminders.setEnabled(value);
      if (value) await widget.reminders.requestPermissions(automatic: true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Promemoria non aggiornati. Riprova.');
      }
    } finally {
      // Read back the durable preference even if scheduling failed.
      final on = await widget.reminders.enabled();
      if (mounted) {
        setState(() {
          enabled = on;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Promemoria Calendario',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            key: const ValueKey('agenda-reminders-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Avvisa 30 minuti prima'),
            subtitle: const Text(
              'Per tutti gli eventi con orario visibili nel Calendario, anche già presenti. Esclusi gli eventi tutto il giorno.',
            ),
            value: enabled ?? true,
            onChanged: enabled == null || busy ? null : _toggle,
          ),
          if (enabled == true && status['notifications'] == false)
            const Text(
              'Le notifiche sono bloccate da Android. Consenti le notifiche per ricevere i promemoria.',
            ),
          if (enabled == true && status['exact'] == false)
            const Text(
              'Consenti sveglie e promemoria per avvisi puntuali. Senza questo permesso Android può ritardarli.',
            ),
          if (enabled == true &&
              (status['notifications'] == false || status['exact'] == false))
            TextButton.icon(
              onPressed: () async {
                try {
                  await widget.reminders.requestPermissions();
                  await _load();
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => error =
                          'Apri le impostazioni Android di Todo per controllare i permessi.',
                    );
                  }
                }
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Consenti in Android'),
            ),
          const Text(
            'Questa scelta vale solo per Todo su questo telefono. Gli eventuali avvisi di Google Calendar o Outlook restano indipendenti.',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
