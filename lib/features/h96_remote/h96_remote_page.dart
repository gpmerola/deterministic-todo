import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'h96_light_card.dart';
import 'h96_remote_client.dart';

/// Remote screen. Connects while visible, disconnects when left or when the
/// app goes to the background: no background work, no polling.
class H96RemotePage extends StatefulWidget {
  const H96RemotePage({this.client, super.key});

  /// Injected in tests; otherwise the page owns its client.
  final H96RemoteClient? client;

  @override
  State<H96RemotePage> createState() => _H96RemotePageState();
}

class _H96RemotePageState extends State<H96RemotePage>
    with WidgetsBindingObserver {
  late final H96RemoteClient _client = widget.client ?? H96RemoteClient();
  final _text = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  List<H96Box>? _found;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      await _client.refresh();
      if (_client.status.value.paired) await _client.connect();
    } on PlatformException {
      // Shown as not paired.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_client.status.value.paired) return;
    if (state == AppLifecycleState.paused) {
      _releaseHeld();
      _client.disconnect();
    }
    if (state == AppLifecycleState.resumed) _client.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseHeld();
    _client.disconnect();
    _client.cancelPairing();
    if (widget.client == null) _client.dispose();
    _text.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _press(String command) async {
    unawaited(HapticFeedback.selectionClick());
    final sent = await _client.send(command);
    if (!sent && mounted) _snack('Telecomando non connesso');
  }

  /// Keys currently held, so leaving the screen always ends the repetition.
  final Set<String> _held = {};

  void _hold(String command, bool start) {
    if (start) {
      unawaited(HapticFeedback.mediumImpact());
      _held.add(command);
    } else if (!_held.remove(command)) {
      return;
    }
    unawaited(_client.hold(command, start: start));
  }

  void _releaseHeld() {
    for (final command in _held.toList()) {
      _hold(command, false);
    }
  }

  Future<void> _sendText() async {
    final text = _text.text;
    if (text.isEmpty) return;
    final sent = await _client.sendText(text);
    if (!mounted) return;
    _snack(sent ? 'Testo inviato alla TV' : 'Telecomando non connesso');
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _found = null;
    });
    try {
      final boxes = await _client.discover();
      if (mounted) setState(() => _found = boxes);
    } on PlatformException {
      if (mounted) setState(() => _found = const []);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualHost() async {
    final controller = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Indirizzo del box'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '192.168.1.50'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (host != null && host.isNotEmpty) {
      await _pair(H96Box(name: host, host: host));
    }
  }

  Future<void> _pair(H96Box box) async {
    setState(() => _busy = true);
    try {
      await _client.startPairing(box.host, name: box.name);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(switch (error.code) {
          'invalid_host' => 'Usa un indirizzo della rete di casa',
          'tls_failed' => 'Il box ha rifiutato la connessione cifrata',
          _ => 'Box non raggiungibile su questa Wi-Fi',
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final paired = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairingCodeDialog(client: _client),
    );
    if (paired == true) {
      await _client.connect();
    } else {
      await _client.cancelPairing();
    }
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dimenticare il box?'),
        content: const Text(
          'Il telefono non sarà più abbinato. Per usarlo di nuovo servirà '
          'un nuovo codice dalla TV.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dimentica'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _client.forget();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<H96Status>(
      valueListenable: _client.status,
      builder: (context, status, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Telecomando'),
          actions: [
            if (status.paired)
              IconButton(
                key: const ValueKey('h96-settings'),
                tooltip: 'Impostazioni del telecomando',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _openSettings(status),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : status.paired
            ? _remote(context, status)
            : _pairingPanel(context),
      ),
    );
  }

  Widget _pairingPanel(BuildContext context) {
    final found = _found;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Telefono e box devono essere sulla stessa Wi-Fi. La TV mostrerà '
          'un codice da inserire qui; nessun dato esce dalla rete di casa.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('h96-discover'),
          onPressed: _busy ? null : _discover,
          icon: const Icon(Icons.search),
          label: const Text('Cerca il box'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _manualHost,
          child: const Text('Inserisci l\'indirizzo a mano'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (found != null && found.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Nessun box trovato su questa Wi-Fi.'),
          ),
        if (found != null)
          for (final box in found)
            ListTile(
              leading: const Icon(Icons.tv),
              title: Text(box.name),
              subtitle: Text(box.host),
              onTap: _busy ? null : () => _pair(box),
            ),
        const Divider(height: 48),
        H96LightCard(
          key: ValueKey('h96-light-$_lightGeneration'),
          client: _client,
        ),
      ],
    );
  }

  /// Bumped to rebuild the light card after forgetting the bulb.
  int _lightGeneration = 0;

  Widget _remote(BuildContext context, H96Status status) {
    final ready = status.ready;
    return Column(
      children: [
        // Only shown when something needs attention.
        if (!ready)
          _ConnectionBanner(
            status: status,
            onRetry: _client.connect,
            onRepair: _forget,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _DirectionPad(enabled: ready, onPressed: _press, onHold: _hold),
              const SizedBox(height: 20),
              Row(
                children: [
                  _RemoteButton(
                    icon: Icons.arrow_back,
                    label: 'Indietro',
                    enabled: ready,
                    onPressed: () => _press('BACK'),
                  ),
                  _RemoteButton(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    enabled: ready,
                    onPressed: () => _press('HOME'),
                  ),
                ],
              ),
              Row(
                children: [
                  _RemoteButton(
                    icon: Icons.volume_down,
                    label: 'Volume giù',
                    enabled: ready,
                    onPressed: () => _press('VOLUME_DOWN'),
                    onHold: (start) => _hold('VOLUME_DOWN', start),
                  ),
                  _RemoteButton(
                    icon: status.muted ? Icons.volume_off : Icons.volume_mute,
                    label: 'Muto',
                    enabled: ready,
                    onPressed: () => _press('MUTE'),
                  ),
                  _RemoteButton(
                    icon: Icons.volume_up,
                    label: 'Volume su',
                    enabled: ready,
                    onPressed: () => _press('VOLUME_UP'),
                    onHold: (start) => _hold('VOLUME_UP', start),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (app, label) in _apps)
                    _AppButton(
                      label: label,
                      enabled: ready,
                      onPressed: () => _launch(app),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('h96-text'),
                controller: _text,
                enabled: ready,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Scrivi sulla TV',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Invia alla TV',
                    icon: const Icon(Icons.send),
                    onPressed: ready ? _sendText : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              H96LightCard(
                key: ValueKey('h96-light-$_lightGeneration'),
                client: _client,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _apps = [
    ('YOUTUBE', 'YouTube'),
    ('NETFLIX', 'Netflix'),
    ('PRIME_VIDEO', 'Prime'),
    ('GOOGLE_PLAY', 'Play'),
  ];

  Future<void> _launch(String app) async {
    unawaited(HapticFeedback.selectionClick());
    final sent = await _client.launch(app);
    if (!sent && mounted) _snack('Telecomando non connesso');
  }

  Future<void> _openSettings(H96Status status) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ValueListenableBuilder<H96Status>(
        valueListenable: _client.status,
        builder: (context, status, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(status.name.isEmpty ? 'Box' : status.name),
                subtitle: Text(status.host),
              ),
              ListTile(
                leading: Icon(
                  status.ready ? Icons.check_circle_outline : Icons.link_off,
                ),
                title: Text(_stateLabel(status)),
                subtitle: status.ready && status.latencyMs > 0
                    ? Text(
                        'Apertura connessione ${status.latencyMs} ms'
                        '${status.latencyMs >= _slowLinkMs ? ': rete lenta' : ''}',
                      )
                    : null,
                trailing: status.ready
                    ? null
                    : TextButton(
                        onPressed: _client.connect,
                        child: const Text('Riprova'),
                      ),
              ),
              if (status.volumeLevel >= 0 && status.volumeMax > 0)
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: Text(
                    'Volume ${status.volumeLevel} su ${status.volumeMax}'
                    '${status.muted ? ', muto' : ''}',
                  ),
                ),
              ListTile(
                key: const ValueKey('h96-forget-light'),
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('Dimentica la lampadina'),
                onTap: () async {
                  Navigator.pop(context);
                  await _client.forgetLight();
                  if (mounted) setState(() => _lightGeneration++);
                },
              ),
              ListTile(
                key: const ValueKey('h96-forget'),
                leading: const Icon(Icons.link_off),
                title: const Text('Dimentica il box'),
                subtitle: const Text('Per abbinarlo di nuovo con un codice'),
                onTap: () {
                  Navigator.pop(context);
                  _forget();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A healthy LAN opens the encrypted connection in about 0.3 s (measured on
/// the H96 Max); above this the link is visibly slow.
const _slowLinkMs = 1500;

String _stateLabel(H96Status status) {
  final name = status.name.isEmpty ? 'box' : status.name;
  return switch (status.state) {
    H96ConnectionState.ready => 'Connesso a $name',
    H96ConnectionState.connecting => 'Connessione…',
    H96ConnectionState.reconnecting => 'Riconnessione…',
    H96ConnectionState.failed when status.failure == H96Failure.notPaired =>
      'Abbinamento non più valido',
    H96ConnectionState.failed => 'Box non raggiungibile',
    H96ConnectionState.idle => 'Non connesso',
  };
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.status,
    required this.onRetry,
    required this.onRepair,
  });

  final H96Status status;
  final VoidCallback onRetry;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final failed = status.state == H96ConnectionState.failed;
    final notPaired = status.failure == H96Failure.notPaired;
    return Material(
      color: failed
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _stateLabel(status),
                key: const ValueKey('h96-status'),
              ),
            ),
            if (failed)
              TextButton(
                onPressed: notPaired ? onRepair : onRetry,
                child: Text(notPaired ? 'Abbina di nuovo' : 'Riprova'),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _Hold = void Function(String command, bool start);

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.enabled,
    required this.onPressed,
    required this.onHold,
  });

  final bool enabled;
  final void Function(String command) onPressed;
  final _Hold onHold;

  @override
  Widget build(BuildContext context) {
    Widget key(String command, IconData icon, String label) => _RoundButton(
      icon: icon,
      label: label,
      enabled: enabled,
      onPressed: () => onPressed(command),
      onHold: (start) => onHold(command, start),
    );
    const gap = SizedBox(
      width: _RoundButton.size + 8,
      height: _RoundButton.size + 8,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [gap, key('UP', Icons.keyboard_arrow_up, 'Su'), gap],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('LEFT', Icons.keyboard_arrow_left, 'Sinistra'),
            _RoundButton(
              label: 'OK',
              enabled: enabled,
              filled: true,
              onPressed: () => onPressed('OK'),
            ),
            key('RIGHT', Icons.keyboard_arrow_right, 'Destra'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [gap, key('DOWN', Icons.keyboard_arrow_down, 'Giù'), gap],
        ),
      ],
    );
  }
}

/// Holding sends a long press the box repeats itself; a quick tap stays a tap.
class _Holdable extends StatelessWidget {
  const _Holdable({required this.enabled, required this.child, this.onHold});

  final bool enabled;
  final ValueChanged<bool>? onHold;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hold = onHold;
    if (hold == null || !enabled) return child;
    return GestureDetector(
      onLongPressStart: (_) => hold(true),
      onLongPressEnd: (_) => hold(false),
      onLongPressCancel: () => hold(false),
      child: child,
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.onHold,
    this.icon,
    this.filled = false,
  });

  static const double size = 76;

  final IconData? icon;
  final String label;
  final bool enabled;
  final bool filled;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onHold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Semantics(
        button: true,
        label: label,
        child: _Holdable(
          enabled: enabled,
          onHold: onHold,
          child: Material(
            color: filled
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: icon == null
                      ? Text(
                          label,
                          style: Theme.of(context).textTheme.titleLarge,
                        )
                      : Icon(icon, size: 40),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  const _RemoteButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.onHold,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onHold;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: _Holdable(
        enabled: enabled,
        onHold: onHold,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: enabled ? onPressed : null,
          child: Tooltip(message: label, child: Icon(icon)),
        ),
      ),
    ),
  );
}

class _AppButton extends StatelessWidget {
  const _AppButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
      ),
    ),
  );
}

class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog({required this.client});

  final H96RemoteClient client;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(code)) {
      setState(() => _error = 'Il codice ha 6 caratteri, cifre e lettere A–F');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.finishPairing(code);
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'bad_code') {
        setState(() {
          _busy = false;
          _error = 'Codice non corretto';
        });
      } else {
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Codice sulla TV'),
    content: TextField(
      key: const ValueKey('h96-code'),
      controller: _code,
      autofocus: true,
      maxLength: 6,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
      ],
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(errorText: _error, hintText: 'A1B2C3'),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('Abbina'),
      ),
    ],
  );
}
