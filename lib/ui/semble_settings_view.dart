import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/task.dart';
import '../services/semble_service.dart';
import 'views/agenda_semble_layer.dart';

/// Semble API key and user id for the Calendar's availability layer
/// (build 285). Read-only: the app never changes anything in Semble.
class SembleSettingsView extends StatefulWidget {
  const SembleSettingsView({
    required this.settings,
    required this.layer,
    this.client,
    DateTime Function()? now,
    super.key,
  }) : now = now ?? DateTime.now;

  final SembleSettings settings;
  final SembleLayer layer;
  final SembleClient? client;
  final DateTime Function() now;

  @override
  State<SembleSettingsView> createState() => _SembleSettingsViewState();
}

class _SembleSettingsViewState extends State<SembleSettingsView> {
  final keyInput = TextEditingController();
  final userInput = TextEditingController();
  final nameInput = TextEditingController();
  final roomInput = TextEditingController();
  late final SembleClient client = widget.client ?? SembleClient();
  SembleConfig? config;
  bool busy = false;
  bool obscured = true;
  bool alerts = true;
  String? status;

  CivilDate get _today => CivilDate.fromDateTime(widget.now());

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    keyInput.dispose();
    userInput.dispose();
    nameInput.dispose();
    roomInput.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = await widget.settings.read();
    final notify = await widget.settings.conflictAlerts();
    if (!mounted) return;
    setState(() {
      config = next;
      alerts = notify;
      if (userInput.text.isEmpty) userInput.text = next.userId ?? '';
      if (nameInput.text.isEmpty) nameInput.text = next.doctorName ?? '';
      if (roomInput.text.isEmpty) roomInput.text = next.roomId ?? '';
    });
  }

  Future<void> _saveAndCheck() async {
    final typed = keyInput.text.trim();
    final user = userInput.text.trim();
    final hasKey = config?.maskedKey != null;
    if (typed.isEmpty && !hasKey) {
      setState(() => status = 'Incolla la chiave API di Semble.');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(user)) {
      setState(() => status = 'Inserisci il tuo User ID Semble.');
      return;
    }
    final room = roomInput.text.trim();
    if (room.isNotEmpty && !RegExp(r'^[A-Za-z0-9]+$').hasMatch(room)) {
      setState(() => status = 'ID stanza non valido: solo lettere e numeri.');
      return;
    }
    setState(() {
      busy = true;
      status = null;
    });
    final key = typed.isEmpty ? await widget.settings.apiKey() : typed;
    try {
      await client.check(key!);
    } on SembleException catch (error) {
      if (error.failure == SembleFailure.rejected) {
        if (!mounted) return;
        setState(() {
          busy = false;
          status = 'Semble ha rifiutato la chiave: non è stata salvata.';
        });
        return;
      }
    }
    await widget.settings.save(
      key: typed.isEmpty ? null : typed,
      userId: user,
      doctorName: nameInput.text,
      roomId: roomInput.text,
    );
    keyInput.clear();
    await widget.layer.reset(today: _today);
    await _reload();
    if (!mounted) return;
    final failure = widget.layer.failure;
    setState(() {
      busy = false;
      status = failure == null
          ? 'Salvato solo su questo telefono. Lette ${widget.layer.ruleCount} '
                'regole di disponibilità.'
          : 'Salvato, ma la lettura non è riuscita: '
                '${SembleException(failure).message}';
    });
  }

  Future<void> _refresh() async {
    setState(() {
      busy = true;
      status = null;
    });
    await widget.layer.reset(today: _today);
    if (!mounted) return;
    final failure = widget.layer.failure;
    setState(() {
      busy = false;
      status = failure == null
          ? 'Lette ${widget.layer.ruleCount} regole.'
          : SembleException(failure).message;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    await widget.settings.setEnabled(enabled);
    await widget.layer.reset(today: _today);
    await _reload();
  }

  Future<void> _clear() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Eliminare la chiave Semble?'),
            content: const Text(
              'Chiave e User ID vengono cancellati da questo telefono e il '
              'Calendario smette di mostrare le disponibilità. La chiave resta '
              'valida in Semble finché un Manager non la revoca.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const ValueKey('semble-confirm-clear'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Elimina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.settings.clear();
    userInput.clear();
    await widget.layer.reset(today: _today);
    await _reload();
    if (mounted) setState(() => status = 'Chiave eliminata.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = config;
    return Scaffold(
      appBar: AppBar(title: const Text('Semble')),
      body: current == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: widget.layer,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Mostra nel Calendario le disponibilità impostate in '
                    'Semble: dietro agli eventi in Giorno, 3 giorni e '
                    'Settimana. '
                    'Sola lettura: Todo non modifica nulla in Semble. Legge '
                    'date e orari delle regole e, per la Stima lavoro '
                    'privato e per il Calendario, orario, tipo, medico ed '
                    'esito (arrivo o DNA) delle prenotazioni, mai i dati dei '
                    'pazienti. Con il cognome impostato le tue prenotazioni '
                    'nuove compaiono nel Calendario prima che arrivino dal '
                    'calendario Google alimentato da Semble, poi resta solo '
                    'la copia Google. La chiave resta '
                    'cifrata su questo telefono: non va nei backup, nei log '
                    'né su Supabase.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _legend(theme),
                  const SizedBox(height: 8),
                  if (current.maskedKey != null)
                    ListTile(
                      key: const ValueKey('semble-current-key'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.key),
                      title: Text('Chiave ${current.maskedKey}'),
                      subtitle: Text(_summary()),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            key: const ValueKey('semble-refresh'),
                            tooltip: 'Rileggi da Semble',
                            onPressed: busy || !current.ready ? null : _refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            key: const ValueKey('semble-clear'),
                            tooltip: 'Elimina chiave',
                            onPressed: busy ? null : _clear,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  if (current.ready)
                    SwitchListTile(
                      key: const ValueKey('semble-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostra nel Calendario'),
                      value: current.enabled,
                      onChanged: busy ? null : _setEnabled,
                    ),
                  if (current.ready)
                    SwitchListTile(
                      key: const ValueKey('semble-conflict-alerts'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Avvisa per eventi in orario Semble'),
                      subtitle: const Text(
                        'Notifica quando arriva un evento in un orario '
                        'prenotabile, anche ad app chiusa. Mostra solo giorno '
                        'e ora.',
                      ),
                      value: alerts,
                      onChanged: busy
                          ? null
                          : (value) async {
                              await widget.settings.setConflictAlerts(value);
                              if (mounted) setState(() => alerts = value);
                            },
                    ),
                  if (current.ready && !widget.layer.zoneMatches)
                    Text(
                      'Il telefono non è nel fuso $sembleZone: orari, '
                      'disponibilità e prenotazioni sono convertiti nell’ora '
                      'del telefono.',
                      key: const ValueKey('semble-zone'),
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('semble-user-input'),
                    controller: userInput,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'User ID Semble',
                      helperText: 'Dal tuo profilo utente nell\'app Semble',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('semble-name-input'),
                    controller: nameInput,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Il tuo cognome in Semble',
                      helperText:
                          'Riconosce le tue prenotazioni: DNA nella stima e '
                          'visite nuove nel Calendario',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('semble-room-input'),
                    controller: roomInput,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'ID stanza Semble (facoltativo)',
                      helperText:
                          'Serve per bloccare orari in Semble dal nuovo '
                          'evento del Calendario',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('semble-key-input'),
                    controller: keyInput,
                    obscureText: obscured,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: current.maskedKey != null
                          ? 'Nuova chiave API (facoltativa)'
                          : 'Chiave API Semble',
                      suffixIcon: IconButton(
                        tooltip: obscured ? 'Mostra' : 'Nascondi',
                        onPressed: () => setState(() => obscured = !obscured),
                        icon: Icon(
                          obscured ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('semble-save'),
                    onPressed: busy ? null : _saveAndCheck,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verifica e salva'),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        status!,
                        key: const ValueKey('semble-status'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _summary() {
    final layer = widget.layer;
    final fetched = layer.fetchedAt;
    if (layer.failure case final failure?) {
      return SembleException(failure).message;
    }
    if (fetched == null || layer.first == null || layer.last == null) {
      return 'Non ancora letta';
    }
    final day = DateFormat('d MMM', 'it');
    final bookings = layer.bookingCount > 0
        ? ' · ${layer.bookingCount} prenotazioni tue nelle prossime 4 '
              'settimane'
        : '';
    return '${layer.ruleCount} regole, dal '
        '${day.format(layer.first!.asLocalDate)} al '
        '${day.format(layer.last!.asLocalDate)} · lette alle '
        '${DateFormat.Hm('it').format(fetched)}$bookings';
  }

  Widget _legend(ThemeData theme) {
    Widget swatch(Color color) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(SemblePalette.legendAvailable(theme.colorScheme)),
            const SizedBox(width: 6),
            const Text('Disponibile'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(SemblePalette.legendUnavailable(theme.colorScheme)),
            const SizedBox(width: 6),
            const Text('Non disponibile (righe)'),
          ],
        ),
      ],
    );
  }
}
