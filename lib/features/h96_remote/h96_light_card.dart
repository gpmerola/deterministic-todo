import 'dart:async';

import 'package:flutter/material.dart';

import 'h96_remote_client.dart';

/// WiZ bulb controls: on/off, brightness and a few colours. Talks to the
/// bulb directly over the home Wi-Fi; nothing goes through the cloud.
class H96LightCard extends StatefulWidget {
  const H96LightCard({required this.client, super.key});

  final H96RemoteClient client;

  @override
  State<H96LightCard> createState() => _H96LightCardState();
}

/// Colour presets: whites as colour temperature, the rest as RGB.
const _presets = <(String, Color, Map<String, Object>)>[
  ('Calda', Color(0xFFFFC27A), {'kind': 'white', 'kelvin': 2700}),
  ('Naturale', Color(0xFFFFF1D6), {'kind': 'white', 'kelvin': 4000}),
  ('Fredda', Color(0xFFE3EEFF), {'kind': 'white', 'kelvin': 6500}),
  ('Rosso', Color(0xFFFF3B30), {'kind': 'color', 'r': 255, 'g': 0, 'b': 0}),
  ('Arancio', Color(0xFFFF9500), {'kind': 'color', 'r': 255, 'g': 120, 'b': 0}),
  ('Verde', Color(0xFF34C759), {'kind': 'color', 'r': 0, 'g': 255, 'b': 0}),
  ('Blu', Color(0xFF0A84FF), {'kind': 'color', 'r': 0, 'g': 0, 'b': 255}),
  ('Viola', Color(0xFFAF52DE), {'kind': 'color', 'r': 150, 'g': 0, 'b': 255}),
];

class _H96LightCardState extends State<H96LightCard> {
  H96Light? _light;
  bool _busy = false;
  double? _dragging;
  Timer? _throttle;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final light = await widget.client.lightState();
      if (mounted) setState(() => _light = light);
    } on Exception {
      if (mounted) setState(() => _light = const H96Light(known: true));
    }
  }

  Future<void> _send(String kind, [Map<String, Object> args = const {}]) async {
    final ok = await widget.client.lightCommand(kind, args);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Lampadina non raggiungibile')),
        );
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    List<H96Bulb> bulbs;
    try {
      bulbs = await widget.client.discoverLights();
    } on Exception {
      bulbs = const [];
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (bulbs.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nessuna lampadina trovata'),
          content: const Text(
            'Il telefono deve essere sulla Wi-Fi di casa e nell\'app WiZ va '
            'attivato «Consenti comunicazione locale».',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final chosen = bulbs.length == 1
        ? bulbs.first
        : await showModalBottomSheet<H96Bulb>(
            context: context,
            showDragHandle: true,
            builder: (context) => ListView(
              shrinkWrap: true,
              children: [
                for (final bulb in bulbs)
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: Text(bulb.host),
                    subtitle: Text(bulb.mac),
                    onTap: () => Navigator.pop(context, bulb),
                  ),
              ],
            ),
          );
    if (chosen == null) return;
    await widget.client.chooseLight(chosen);
    await _refresh();
  }

  void _onSlide(double value) {
    setState(() => _dragging = value);
    // Live preview while dragging, at most five commands a second.
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 200), () {
      final current = _dragging;
      if (current != null) _send('dimming', {'value': current.round()});
    });
  }

  void _onSlideEnd(double value) {
    _throttle?.cancel();
    setState(() {
      _dragging = null;
      _light = _light?.copyWith(dimming: value.round(), on: true);
    });
    _send('dimming', {'value': value.round()});
  }

  @override
  Widget build(BuildContext context) {
    final light = _light;
    if (light == null) return const SizedBox.shrink();
    if (!light.known) {
      return OutlinedButton.icon(
        key: const ValueKey('h96-light-connect'),
        onPressed: _busy ? null : _connect,
        icon: const Icon(Icons.lightbulb_outline),
        label: Text(_busy ? 'Ricerca…' : 'Collega la lampadina WiZ'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(light.on ? Icons.lightbulb : Icons.lightbulb_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                light.reachable ? 'Luce' : 'Luce non raggiungibile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!light.reachable)
              TextButton(onPressed: _refresh, child: const Text('Riprova'))
            else
              Switch(
                key: const ValueKey('h96-light-switch'),
                value: light.on,
                onChanged: (on) {
                  setState(() => _light = light.copyWith(on: on));
                  _send('power', {'on': on});
                },
              ),
          ],
        ),
        Slider(
          key: const ValueKey('h96-light-dimming'),
          min: 10,
          max: 100,
          value: (_dragging ?? light.dimming.toDouble()).clamp(10, 100),
          label: '${(_dragging ?? light.dimming).round()}%',
          divisions: 18,
          onChanged: light.reachable ? _onSlide : null,
          onChangeEnd: light.reachable ? _onSlideEnd : null,
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final (label, color, args) in _presets)
              Tooltip(
                message: label,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: light.reachable
                      ? () {
                          setState(() => _light = light.copyWith(on: true));
                          final kind = args['kind']! as String;
                          _send(kind, {...args}..remove('kind'));
                        }
                      : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
