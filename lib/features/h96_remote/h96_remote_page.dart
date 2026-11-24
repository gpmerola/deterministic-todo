import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          title: const Text('Telecomando TV'),
          actions: [
            if (status.paired)
              PopupMenuButton<String>(
                onSelected: (_) => _forget(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'forget',
                    child: Text('Dimentica il box'),
                  ),
                ],
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
      ],
    );
  }

  Widget _remote(BuildContext context, H96Status status) {
    // The status stays pinned above the scrolling controls.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _StatusBar(
            status: status,
            onRetry: _client.connect,
            onRepair: _forget,
          ),
        ),
        Expanded(child: _controls(context, status)),
      ],
    );
  }

  Widget _controls(BuildContext context, H96Status status) {
    final ready = status.ready;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DirectionPad(enabled: ready, onPressed: _press, onHold: _hold),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _RemoteButton(
                icon: Icons.arrow_back,
                label: 'Indietro',
                enabled: ready,
                onPressed: () => _press('BACK'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RemoteButton(
                icon: Icons.home_outlined,
                label: 'Home',
                enabled: ready,
                onPressed: () => _press('HOME'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RemoteButton(
                icon: Icons.volume_down,
                label: 'Volume giù',
                enabled: ready,
                onPressed: () => _press('VOLUME_DOWN'),
                onHold: (start) => _hold('VOLUME_DOWN', start),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RemoteButton(
                icon: status.muted ? Icons.volume_off : Icons.volume_mute,
                label: 'Muto',
                enabled: ready,
                onPressed: () => _press('MUTE'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RemoteButton(
                icon: Icons.volume_up,
                label: 'Volume su',
                enabled: ready,
                onPressed: () => _press('VOLUME_UP'),
                onHold: (start) => _hold('VOLUME_UP', start),
              ),
            ),
          ],
        ),
        if (status.volumeLevel >= 0 && status.volumeMax > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Volume ${status.volumeLevel} su ${status.volumeMax}'
              '${status.muted ? ', muto' : ''}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('h96-text'),
          controller: _text,
          enabled: ready,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendText(),
          decoration: InputDecoration(
            labelText: 'Testo per il campo attivo sulla TV',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Invia alla TV',
              icon: const Icon(Icons.send),
              onPressed: ready ? _sendText : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ready ? () => _press('DELETE') : null,
                icon: const Icon(Icons.backspace_outlined),
                label: const Text('Cancella'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ready ? () => _press('ENTER') : null,
                icon: const Icon(Icons.keyboard_return),
                label: const Text('Invio'),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Svuota',
              onPressed: _text.clear,
              icon: const Icon(Icons.clear),
            ),
          ],
        ),
      ],
    );
  }
}

/// A healthy LAN opens the encrypted connection in about 0.3 s (measured on
/// the H96 Max); above this the link is visibly slow.
const _slowLinkMs = 1500;

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.onRetry,
    required this.onRepair,
  });

  final H96Status status;
  final VoidCallback onRetry;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = status.name.isEmpty ? 'box' : status.name;
    final (IconData icon, Color color, String text) = switch (status.state) {
      H96ConnectionState.ready => (
        Icons.check_circle,
        scheme.primary,
        'Connesso a $name',
      ),
      H96ConnectionState.connecting => (
        Icons.sync,
        scheme.outline,
        'Connessione…',
      ),
      H96ConnectionState.reconnecting => (
        Icons.sync,
        scheme.tertiary,
        'Riconnessione…',
      ),
      H96ConnectionState.failed => (
        Icons.error_outline,
        scheme.error,
        status.failure == H96Failure.notPaired
            ? 'Abbinamento non più valido'
            : 'Box non raggiungibile',
      ),
      H96ConnectionState.idle => (
        Icons.link_off,
        scheme.outline,
        'Non connesso',
      ),
    };
    final slow = status.ready && status.latencyMs >= _slowLinkMs;
    return Row(
      children: [
        Icon(
          slow ? Icons.network_check : icon,
          color: slow ? scheme.tertiary : color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, key: const ValueKey('h96-status')),
              if (slow)
                Text(
                  'Rete lenta verso il box: i tasti possono arrivare in ritardo',
                  key: const ValueKey('h96-slow'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (status.state == H96ConnectionState.failed)
          status.failure == H96Failure.notPaired
              ? TextButton(
                  onPressed: onRepair,
                  child: const Text('Abbina di nuovo'),
                )
              : TextButton(onPressed: onRetry, child: const Text('Riprova')),
      ],
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

/// Wraps a button so that holding it sends a long press the box repeats
/// itself, and releasing it ends the repetition. A quick tap stays a tap.
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
  Widget build(BuildContext context) => _Holdable(
    enabled: enabled,
    onHold: onHold,
    child: FilledButton.tonal(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: enabled ? onPressed : null,
      child: Tooltip(message: label, child: Icon(icon)),
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
