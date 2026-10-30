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
  final icalInput = TextEditingController();
  late final SembleClient client = widget.client ?? SembleClient();
  SembleConfig? config;
  bool busy = false;
  bool obscured = true;
  bool alerts = true;
  String? status;

  /// The iCal link is saved (build 312); the link itself is not shown.
  bool hasLink = false;

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
    icalInput.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = await widget.settings.read();
    final notify = await widget.settings.conflictAlerts();
    final link = await widget.settings.icalLink();
    if (!mounted) return;
    setState(() {
      config = next;
      alerts = notify;
      hasLink = link != null;
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

  /// Saves the iCal link and reads it at once (build 312).
  Future<void> _saveLink() async {
    final typed = icalInput.text.trim();
    if (sembleIcalUri(typed) == null) {
      setState(
        () => status = const SembleIcalException(
          SembleIcalFailure.invalid,
        ).message,
      );
      return;
    }
    setState(() {
      busy = true;
      status = null;
    });
    await widget.settings.saveIcalLink(typed);
    icalInput.clear();
    await _reload();
    await widget.layer.reset(today: _today);
    if (!mounted) return;
    final failure = widget.layer.icalFailure;
    setState(() {
      busy = false;
      status = switch (failure) {
        final failure? =>
          'Link salvato, ma la lettura non è riuscita: '
              '${SembleIcalException(failure).message}',
        null when widget.layer.bookingsSource == SembleBookingsSource.ical =>
          'Link salvato. Lette ${widget.layer.bookingCount} visite delle '
              'prossime 4 settimane.',
        // The key works: the link stays ready for when it stops.
        null => 'Link salvato: sarà usato se la chiave smette di funzionare.',
      };
    });
  }

  Future<void> _deleteLink() async {
    await widget.settings.deleteIcalLink();
    await _reload();
    await widget.layer.reset(today: _today);
    if (mounted) setState(() => status = 'Link iCal eliminato.');
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
                  // Build 306: state first, then what it does in the
                  // Calendar, then the connection, folded once it works.
                  if (current.maskedKey != null || hasLink)
                    ListTile(
                      key: const ValueKey('semble-current-key'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.key),
                      title: Text(
                        current.maskedKey != null
                            ? 'Chiave ${current.maskedKey}'
                            : 'Senza chiave: solo link iCal',
                      ),
                      subtitle: Text(_summary()),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            key: const ValueKey('semble-refresh'),
                            tooltip: 'Rileggi da Semble',
                            onPressed: busy || !(current.ready || hasLink)
                                ? null
                                : _refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                          if (current.maskedKey != null)
                            IconButton(
                              key: const ValueKey('semble-clear'),
                              tooltip: 'Elimina chiave',
                              onPressed: busy ? null : _clear,
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                    ),
                  if (current.ready || hasLink) ...[
                    _heading(theme, 'Nel Calendario'),
                    SwitchListTile(
                      key: const ValueKey('semble-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostra disponibilità e visite'),
                      value: current.enabled,
                      onChanged: busy ? null : _setEnabled,
                    ),
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
                    _legend(theme),
                    if (!widget.layer.zoneMatches)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Il telefono non è nel fuso $sembleZone: orari, '
                          'disponibilità e prenotazioni sono convertiti '
                          'nell’ora del telefono.',
                          key: const ValueKey('semble-zone'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  ExpansionTile(
                    key: const ValueKey('semble-connection'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded: !current.ready,
                    title: const Text('Collegamento'),
                    subtitle: const Text('User ID, cognome, stanza e chiave'),
                    children: [
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
                              'Riconosce le tue prenotazioni: DNA nella stima '
                              'e visite nuove nel Calendario',
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
                              'Serve per bloccare orari in Semble dal '
                              'Calendario',
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
                            onPressed: () =>
                                setState(() => obscured = !obscured),
                            icon: Icon(
                              obscured
                                  ? Icons.visibility
                                  : Icons.visibility_off,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Verifica e salva'),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    key: const ValueKey('semble-ical'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded:
                        !hasLink &&
                        widget.layer.failure == SembleFailure.rejected,
                    title: const Text('Riserva senza chiave'),
                    subtitle: Text(
                      hasLink
                          ? 'Link iCal salvato'
                          : 'Link iCal di Semble, per le visite',
                    ),
                    children: [
                      Text(
                        'Se la chiave manca o Semble la rifiuta, le visite '
                        'arrivano dal link iCal del tuo calendario Semble '
                        '(lo stesso che alimenta il calendario Google), '
                        'senza aspettare Google. Senza link le visite '
                        'restano quelle del calendario Google «Semble»; le '
                        'disponibilità già lette restano nel Calendario, con '
                        'la data dell\'ultima lettura.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('semble-ical-input'),
                        controller: icalInput,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: hasLink
                              ? 'Nuovo link iCal (facoltativo)'
                              : 'Link iCal (https:// o webcal://)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            key: const ValueKey('semble-ical-save'),
                            onPressed: busy ? null : _saveLink,
                            child: const Text('Salva link'),
                          ),
                          if (hasLink)
                            TextButton(
                              key: const ValueKey('semble-ical-delete'),
                              onPressed: busy ? null : _deleteLink,
                              child: const Text('Elimina link'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        status!,
                        key: const ValueKey('semble-status'),
                      ),
                    ),
                  ExpansionTile(
                    key: const ValueKey('semble-privacy'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Cosa legge e cosa scrive'),
                    children: [
                      Text(
                        'Legge date e orari delle regole di disponibilità e, '
                        'delle prenotazioni, orario, tipo, medico ed esito '
                        '(arrivo o DNA): mai i dati dei pazienti. Scrive in '
                        'Semble solo quando tocchi «Blocca» (un orario non '
                        'disponibile, tipo Other) o il suo «Annulla». Con il '
                        'cognome impostato le tue prenotazioni nuove compaiono '
                        'nel Calendario prima che arrivino dal calendario '
                        'Google alimentato da Semble. Con il link iCal legge '
                        'del feed solo orario, titolo e annullamento. Chiave, '
                        'link e ultime disponibilità lette restano cifrati su questo '
                        'telefono: non vanno nei backup, nei log né su '
                        'Supabase.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  String _summary() {
    final layer = widget.layer;
    final day = DateFormat('d MMM', 'it');
    final time = DateFormat.Hm('it');
    String when(DateTime at) => '${day.format(at)} alle ${time.format(at)}';
    final parts = <String>[
      if (layer.failure case final failure? when failure != SembleFailure.noKey)
        SembleException(failure).message,
    ];
    if (layer.first case final first? when layer.last != null) {
      final rules =
          '${layer.ruleCount} regole, dal ${day.format(first.asLocalDate)} '
          'al ${day.format(layer.last!.asLocalDate)}';
      final saved = layer.rulesSavedAt;
      parts.add(switch ((layer.rulesFromCache, saved)) {
        (false, final at?) => '$rules · lette alle ${time.format(at)}',
        (true, final at?) => '$rules · ultima lettura il ${when(at)}',
        _ => '$rules · da una lettura precedente',
      });
    }
    final count = layer.bookingCount;
    final bookingsAt = layer.bookingsSavedAt;
    switch (layer.bookingsSource) {
      case SembleBookingsSource.api when count > 0:
        parts.add('$count prenotazioni tue nelle prossime 4 settimane');
      case SembleBookingsSource.ical when bookingsAt != null:
        parts.add(
          '$count visite dal link iCal, lette alle ${time.format(bookingsAt)}',
        );
      case SembleBookingsSource.google:
        parts.add(
          layer.googleCalendarVisible == false
              ? 'Calendario Google «Semble» assente o nascosto: le visite '
                    'non compaiono'
              : 'visite dal calendario Google «Semble» (aggiornato ogni 30 '
                    'minuti)',
        );
      default:
    }
    if (layer.icalFailure case final failure?) {
      parts.add(SembleIcalException(failure).message);
    }
    return parts.isEmpty ? 'Non ancora letta' : parts.join(' · ');
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
