import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'agenda_backup.dart';
import 'agenda_mirror.dart';
import 'agenda_requests.dart';
import 'agenda_service.dart';

/// What the phone does for the web Agenda: apply queued web edits, then
/// refresh the mirror. Driven by app start/resume and by the Android
/// background job (calendar changed, or hourly); never by a timer.
class AgendaPhoneSync {
  AgendaPhoneSync({
    required AgendaService service,
    required this.client,
    required String deviceId,
    AgendaRequestProcessor? processor,
    AgendaMirror? mirror,
    AgendaBackup? backup,
  }) : service = service,
       backup =
           backup ??
           AgendaBackup(service: service, client: client, deviceId: deviceId),
       processor =
           processor ??
           AgendaRequestProcessor(service: service, client: client),
       mirror =
           mirror ??
           AgendaMirror(service: service, client: client, deviceId: deviceId);

  static const channel = MethodChannel('app.deterministic.todo/agenda');
  static const backgroundChannel = MethodChannel(
    'app.deterministic.todo/agenda_background',
  );

  final AgendaService service;
  final SupabaseClient client;
  final AgendaRequestProcessor processor;
  final AgendaMirror mirror;

  /// Supabase backup of Todo's own calendar and Agenda choices (build 227).
  final AgendaBackup backup;

  /// App start and resume: throttled by the processor and the mirror. Also
  /// re-arms the jobs, which a signed-out background run cancels.
  Future<void> foreground() async {
    if (client.auth.currentSession != null) await _schedule();
    final handled = await processor.processIfStale();
    if (handled > 0) {
      await mirror.upload();
    } else {
      await mirror.uploadIfStale();
    }
    // Local work only, unless something changed since the last backup.
    await backup.save();
  }

  /// After a change made in the Agenda: the mirror, then the backup.
  Future<void> changed() async {
    await mirror.upload();
    await backup.save();
  }

  /// One background run; the result tells the Android job what to do next:
  /// `done` (remember this calendar state), `retry`, or `stop` (not signed
  /// in or no calendar access: the jobs are cancelled until the app
  /// schedules them again).
  Future<String> background(String reason) async {
    if (client.auth.currentSession == null) return 'stop';
    if (await service.access() != AgendaAccess.granted) return 'stop';
    final handled = await processor.process();
    var uploaded = true;
    if (reason == 'calendar' || handled > 0) uploaded = await mirror.upload();
    // A failed backup does not ask for retries: the next run or the next
    // app start tries again, and an unchanged backup costs no network.
    await backup.save();
    return uploaded ? 'done' : 'retry';
  }

  /// Lets the background job reach this engine while the app is alive, and
  /// arms the jobs. Missing native side (tests, other platforms) is fine.
  Future<void> attach() async {
    AgendaBackup.current = backup;
    backgroundChannel.setMethodCallHandler((call) async {
      if (call.method != 'run') throw MissingPluginException();
      return background(call.arguments as String? ?? 'periodic');
    });
    await _schedule();
  }

  Future<void> _schedule() async {
    try {
      await channel.invokeMethod<void>('scheduleBackground');
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Scheduling refused: start and resume still keep the web current.
    }
  }

  void detach() => backgroundChannel.setMethodCallHandler(null);
}
