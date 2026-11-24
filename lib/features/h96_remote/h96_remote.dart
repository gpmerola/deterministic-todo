/// H96 Remote: Android TV remote for the H96 Max box, kept as an isolated feature.
///
/// The rest of the app touches it only through [H96RemoteSettingsTile].
/// Switch off with `--dart-define=H96_REMOTE=false`; remove by deleting this
/// folder, `android/h96remote` and the lines listed in
/// docs/architecture/H96_REMOTE.md.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// The single entry point shown in Settings; empty when unavailable.
class H96RemoteSettingsTile extends StatelessWidget {
  const H96RemoteSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    if (!h96RemoteAvailable) return const SizedBox.shrink();
    return ListTile(
      key: const ValueKey('settings-h96-remote'),
      leading: const Icon(Icons.settings_remote_outlined),
      title: const Text('Telecomando TV'),
      subtitle: const Text('TV Box H96 Max sulla Wi-Fi di casa'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const H96RemotePage())),
    );
  }
}
