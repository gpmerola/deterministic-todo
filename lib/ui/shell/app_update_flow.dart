import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/diagnostic_log_service.dart';
import '../../services/platform_runtime_native.dart'
    if (dart.library.js_interop) '../../services/platform_runtime_web.dart';
import '../../services/play_update_service.dart';
import '../../services/update_service.dart';

const isPlayDistribution =
    String.fromEnvironment('DISTRIBUTION_CHANNEL') == 'play';

/// Update check and installation, owned by the shell but independent of its
/// state. Automatic checks are rate limited by [isDue]; each channel keeps
/// its own signing line (Play in-app update or direct APK with SHA-256).
class AppUpdateFlow {
  static const automaticInterval = Duration(hours: 6);

  bool _checking = false;
  DateTime? _lastCheck;

  bool isDue(DateTime now) =>
      _lastCheck == null || now.difference(_lastCheck!) >= automaticInterval;

  Future<void> check(BuildContext context, {bool automatic = false}) async {
    if (isPlayDistribution) {
      await _checkPlayUpdate(context, automatic: automatic);
      return;
    }
    if (_checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    final elapsed = Stopwatch()..start();
    var result = 'current';
    try {
      final update = await UpdateService().check();
      if (update == null || !context.mounted) return;
      result = 'available';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aggiornamento disponibile'),
          content: Text(
            'È disponibile la versione ${update.version}. '
            'I dati locali non verranno eliminati.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Più tardi'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                if (!context.mounted) return;
                await _installUpdate(context, update);
              },
              child: const Text('Aggiorna'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      result = 'error';
      unawaited(
        DiagnosticLogService.instance.event(
          'update_check',
          level: 'warning',
          fields: {
            'channel': 'direct',
            'result': result,
            'automatic': automatic,
            'error_type': error.runtimeType.toString(),
            'duration_ms': elapsed.elapsedMilliseconds,
          },
        ),
      );
      // Offline, timeout o manifest non valido: l'uso locale continua.
    } finally {
      elapsed.stop();
      if (result != 'error') {
        unawaited(
          DiagnosticLogService.instance.event(
            'update_check',
            fields: {
              'channel': 'direct',
              'result': result,
              'automatic': automatic,
              'duration_ms': elapsed.elapsedMilliseconds,
            },
          ),
        );
      }
      _checking = false;
    }
  }

  Future<void> _checkPlayUpdate(
    BuildContext context, {
    required bool automatic,
  }) async {
    if (_checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    final elapsed = Stopwatch()..start();
    var status = PlayUpdateStatus.error;
    try {
      status = await PlayUpdateService().check(startIfAvailable: true);
      if (!automatic && context.mounted) {
        if (status == PlayUpdateStatus.unavailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('L’app è aggiornata'),
              showCloseIcon: true,
            ),
          );
        } else if (status == PlayUpdateStatus.available ||
            status == PlayUpdateStatus.unsupported ||
            status == PlayUpdateStatus.error) {
          await _openPlayStoreListing(context);
        }
      }
    } finally {
      elapsed.stop();
      unawaited(
        DiagnosticLogService.instance.event(
          'update_check',
          level: status == PlayUpdateStatus.error ? 'warning' : 'info',
          fields: {
            'channel': 'play',
            'result': status.name,
            'automatic': automatic,
            'duration_ms': elapsed.elapsedMilliseconds,
          },
        ),
      );
      _checking = false;
    }
  }

  Future<void> _openPlayStoreListing(BuildContext context) async {
    const packageName = 'app.deterministic.todo.deterministic_todo';
    final marketUri = Uri.parse('market://details?id=$packageName');
    final webUri = Uri.https('play.google.com', '/store/apps/details', {
      'id': packageName,
    });
    try {
      if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } on Object {
      // Alcuni dispositivi non espongono lo schema market://.
    }
    final opened = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile aprire Google Play'),
          showCloseIcon: true,
        ),
      );
    }
  }

  Future<void> _installUpdate(
    BuildContext context,
    AvailableUpdate update,
  ) async {
    if (!isAndroidPlatform) {
      await launchUrl(update.url, mode: LaunchMode.externalApplication);
      return;
    }
    if (!await UpdateService.stillApplies(update)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L’app è già aggiornata'),
            showCloseIcon: true,
          ),
        );
      }
      return;
    }
    final ota = OtaUpdate();
    final events = ota.execute(
      update.url.toString(),
      destinationFilename:
          'deterministic-todo-${update.version}-${update.build}.apk',
      sha256checksum: update.sha256,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamBuilder<OtaEvent>(
        stream: events,
        builder: (context, snapshot) {
          final event = snapshot.data;
          final progress = event?.status == OtaStatus.DOWNLOADING
              ? double.tryParse(event?.value ?? '')
              : null;
          final failed =
              event != null &&
              {
                OtaStatus.ALREADY_RUNNING_ERROR,
                OtaStatus.INSTALLATION_ERROR,
                OtaStatus.PERMISSION_NOT_GRANTED_ERROR,
                OtaStatus.INTERNAL_ERROR,
                OtaStatus.DOWNLOAD_ERROR,
                OtaStatus.CHECKSUM_ERROR,
              }.contains(event.status);
          final message = switch (event?.status) {
            OtaStatus.DOWNLOADING => 'Download ${event?.value ?? '0'}%',
            OtaStatus.INSTALLING => 'Apro l’installazione Android…',
            OtaStatus.INSTALLATION_DONE => 'Aggiornamento installato',
            OtaStatus.CHECKSUM_ERROR => 'Il file scaricato non è valido.',
            OtaStatus.PERMISSION_NOT_GRANTED_ERROR =>
              'Autorizza l’installazione da questa app nelle impostazioni Android.',
            null => 'Preparo il download…',
            _ when failed => 'Aggiornamento non riuscito. Riprova.',
            _ => 'Aggiornamento in preparazione…',
          };
          return AlertDialog(
            title: Text('Aggiornamento ${update.version}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress == null ? null : progress / 100,
                ),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
            actions: [
              if (failed)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Chiudi'),
                )
              else
                TextButton(
                  onPressed: () async {
                    await ota.cancel();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Annulla'),
                ),
            ],
          );
        },
      ),
    );
  }
}
