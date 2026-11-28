/// H96 Remote: Android TV remote for the H96 Max box, kept as an isolated feature.
///
/// The rest of the app touches it only through [H96RemoteAction] (Today bar).
/// Switch off with `--dart-define=H96_REMOTE=false`; remove by deleting this
/// folder, `android/h96remote` and the lines listed in
/// docs/architecture/H96_REMOTE.md.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'h96_light_card.dart';
import 'h96_remote_page.dart';

/// Compile-time switch for the whole feature.
const bool h96RemoteEnabled = bool.fromEnvironment(
  'H96_REMOTE',
  defaultValue: true,
);

/// Android only: the browser cannot open TLS sockets to a LAN device.
bool get h96RemoteAvailable =>
    h96RemoteEnabled &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android;

/// Quick entries in the Today app bar, next to the step counter: the light
/// sheet and the remote.
class H96RemoteAction extends StatelessWidget {
  const H96RemoteAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (!h96RemoteAvailable) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('h96-light-open'),
          tooltip: 'Luce',
          icon: const Icon(Icons.lightbulb_outline),
          onPressed: () => H96LightSheet.show(context),
        ),
        IconButton(
          key: const ValueKey('h96-remote-open'),
          tooltip: 'Telecomando TV',
          icon: const Icon(Icons.settings_remote_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const H96RemotePage()),
          ),
        ),
      ],
    );
  }
}
