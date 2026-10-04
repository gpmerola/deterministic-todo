import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  }) : service = service,
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

  /// App start and resume: throttled by the processor and the mirror.
  Future<void> foreground() async {
    final handled = await processor.processIfStale();
    if (handled > 0) {
      await mirror.upload();
    } else {
      await mirror.uploadIfStale();
    }
  }

  /// One background run; the result tells the Android job what to do next:
  /// `done` (remember this calendar state), `retry`, or `stop` (not signed
  /// in or no calendar access: the jobs are cancelled until the app
  /// schedules them again).
  Future<String> background(String reason) async {
    if (client.auth.currentSession == null) return 'stop';
    if (await service.access() != AgendaAccess.granted) return 'stop';
    final handled = await processor.process();
    if (reason == 'calendar' || handled > 0) {
      return await mirror.upload() ? 'done' : 'retry';
    }
    return 'done';
  }

  /// Lets the background job reach this engine while the app is alive, and
  /// arms the jobs. Missing native side (tests, other platforms) is fine.
  Future<void> attach() async {
    backgroundChannel.setMethodCallHandler((call) async {
      if (call.method != 'run') throw MissingPluginException();
      return background(call.arguments as String? ?? 'periodic');
    });
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
