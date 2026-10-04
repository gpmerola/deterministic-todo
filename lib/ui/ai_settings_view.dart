import 'package:flutter/material.dart';

import '../services/ai_settings.dart';

/// Where the user stores an LLM API key. Nothing in the app sends data to the
/// provider yet; future features must ask explicitly each time.
class AiSettingsView extends StatefulWidget {
  const AiSettingsView({required this.settings, super.key});

  final AiSettings settings;

  @override
  State<AiSettingsView> createState() => _AiSettingsViewState();
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final keyInput = TextEditingController();
  AiConfig? config;
  AiProvider provider = AiProvider.deepseek;
  bool busy = false;
  bool obscured = true;
  String? status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    keyInput.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = await widget.settings.read();
    if (!mounted) return;
    setState(() {
      config = next;
      provider = next.provider;
    });
  }

  Future<void> _saveAndCheck() async {
    final key = keyInput.text.trim();
    if (key.isEmpty) {
      setState(() => status = 'Incolla la chiave API.');
      return;
    }
    setState(() {
      busy = true;
      status = null;
    });
    final result = await widget.settings.check(provider, key);
    if (result == AiKeyCheck.rejected) {
      if (!mounted) return;
      setState(() {
        busy = false;
        status =
            '${provider.label} ha rifiutato la chiave: non è stata salvata.';
      });
      return;
    }
    await widget.settings.save(provider, key);
    keyInput.clear();
    await _reload();
    if (!mounted) return;
    setState(() {
      busy = false;
      status = result == AiKeyCheck.valid
          ? 'Chiave verificata e salvata solo su questo telefono.'
          : 'Chiave salvata, ma la verifica non è riuscita (rete o servizio). '
                'Riprova più tardi.';
    });
  }

  Future<void> _check() async {
    final key = await widget.settings.apiKey();
    if (key == null) return;
    setState(() {
      busy = true;
      status = null;
    });
    final result = await widget.settings.check(config!.provider, key);
    if (!mounted) return;
    setState(() {
      busy = false;
      status = switch (result) {
        AiKeyCheck.valid => 'La chiave funziona.',
        AiKeyCheck.rejected => 'La chiave non è più valida.',
        AiKeyCheck.unreachable => 'Servizio non raggiungibile: riprova.',
      };
    });
  }

  Future<void> _clear() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Eliminare la chiave?'),
            content: const Text(
              'La chiave viene cancellata da questo telefono. Per revocarla '
              'del tutto, eliminala anche dalla console del fornitore.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const ValueKey('ai-confirm-clear'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Elimina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.settings.clear();
    await _reload();
    if (mounted) setState(() => status = 'Chiave eliminata.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = config;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente AI')),
      body: current == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'La chiave resta cifrata solo su questo telefono: non va '
                  'nei backup, nei log né su Supabase. Per ora nessuna '
                  'funzione la usa; le future funzioni AI chiederanno '
                  'conferma prima di inviare qualunque testo e non '
                  'invieranno mai eventi del calendario senza un tuo '
                  'consenso esplicito.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (current.hasKey)
                  ListTile(
                    key: const ValueKey('ai-current-key'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key),
                    title: Text(current.provider.label),
                    subtitle: Text('Chiave ${current.maskedKey}'),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Verifica',
                          onPressed: busy ? null : _check,
                          icon: const Icon(Icons.verified_outlined),
                        ),
                        IconButton(
                          key: const ValueKey('ai-clear'),
                          tooltip: 'Elimina chiave',
                          onPressed: busy ? null : _clear,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AiProvider>(
                  key: const ValueKey('ai-provider'),
                  initialValue: provider,
                  decoration: const InputDecoration(labelText: 'Fornitore'),
                  items: [
                    for (final option in AiProvider.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(
                          () => provider = value ?? AiProvider.deepseek,
                        ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ai-key-input'),
                  controller: keyInput,
                  obscureText: obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: current.hasKey
                        ? 'Nuova chiave API (sostituisce quella salvata)'
                        : 'Chiave API',
                    hintText: provider.keyHint,
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
                  key: const ValueKey('ai-save'),
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
                    child: Text(status!, key: const ValueKey('ai-status')),
                  ),
              ],
            ),
    );
  }
}
