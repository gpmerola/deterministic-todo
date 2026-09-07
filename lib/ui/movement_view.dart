import 'dart:async';

import 'package:flutter/material.dart';

import '../services/run_tracker_service.dart';
import 'movement_profile_dialog.dart';

class MovementView extends StatefulWidget {
  const MovementView({
    required this.dailyMovement,
    required this.stepGoal,
    required this.refreshDailyMovement,
    super.key,
  });

  final DailyMovementProgress? dailyMovement;
  final int stepGoal;
  final Future<void> Function() refreshDailyMovement;

  @override
  State<MovementView> createState() => _MovementViewState();
}

class _MovementViewState extends State<MovementView>
    with WidgetsBindingObserver {
  Timer? timer;
  MovementSessionState? session;
  String? pendingStart;
  bool retryingPermission = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && pendingStart != null) {
      retryingPermission = true;
      unawaited(_start(pendingStart!));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = await RunTrackerService.movementState();
    if (!mounted) return;
    setState(() => session = next);
  }

  Future<void> _editProfile() async {
    try {
      final profile = await RunTrackerService.movementProfile();
      if (!mounted) return;
      final values = await showDialog<Map<String, double>>(
        context: context,
        builder: (_) => MovementProfileDialog(values: profile),
      );
      if (values == null) return;
      await RunTrackerService.saveMovementProfile(values);
      await widget.refreshDailyMovement();
    } catch (_) {
      if (mounted) _message('Impossibile salvare il profilo movimento.');
    }
  }

  Future<void> _enableSteps() async {
    try {
      await RunTrackerService.requestStepPermission();
      await widget.refreshDailyMovement();
    } catch (_) {
      if (mounted) {
        _message('Controlla il permesso Attività fisica nelle impostazioni.');
      }
    }
  }

  String _collectionLabel(DailyMovementProgress? daily) {
    final status = daily?.collectionStatus ?? 'not_started';
    if (status == 'subscribed_no_samples') {
      return 'Raccolta attiva · dati non ancora disponibili.';
    }
    if (status == 'permission_required') {
      return 'Consenti Attività fisica per contare i passi.';
    }
    if (status == 'subscribed') {
      if (daily?.coverage == 'retention_gap') {
        return 'Conteggio attivo · alcuni intervalli non recuperabili.';
      }
      if (daily?.lastImport != null &&
          DateTime.now().difference(daily!.lastImport!) >
              const Duration(hours: 6)) {
        return 'Ultimo aggiornamento dei passi in ritardo.';
      }
      return 'Passi in background · aggiornati al minuto completo.';
    }
    if (status == 'awaiting_complete_minute') {
      return 'Conteggio attivato · in attesa del primo minuto.';
    }
    if (status == 'subscribing' ||
        status == 'reading' ||
        status == 'not_started') {
      return 'Aggiornamento dei passi…';
    }
    return 'Conteggio non disponibile · dati salvati conservati. Controlla permessi e Play Services.';
  }

  Future<void> _start(String type) async {
    if (busy) return;
    setState(() => busy = true);
    final outcome = await RunTrackerService.startMovement(type);
    if (!mounted) return;
    setState(() => busy = false);
    if (outcome == 'permission_requested') {
      if (retryingPermission) {
        retryingPermission = false;
        pendingStart = null;
        _message('Servono posizione precisa e attività fisica per registrare.');
      } else {
        pendingStart = type;
      }
      return;
    }
    retryingPermission = false;
    pendingStart = null;
    await _refresh();
  }

  Future<void> _stop() async {
    if (busy) return;
    setState(() => busy = true);
    await RunTrackerService.stopMovement();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await Future.wait([_refresh(), widget.refreshDailyMovement()]);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _upload() async {
    if (busy) return;
    setState(() => busy = true);
    final outcome = await RunTrackerService.uploadMovementData();
    if (!mounted) return;
    setState(() => busy = false);
    _message(switch (outcome) {
      'success' => 'Bundle diagnostico verificato su Drive.',
      'drive_not_configured' =>
        'Collega prima la cartella Drive dagli strumenti avanzati.',
      'permission_failure' =>
        'Autorizzazione Drive scaduta: ricollega la cartella.',
      _ => 'Upload non riuscito. Il dettaglio è stato registrato.',
    });
  }

  Future<void> _setPassiveMonitoring(bool enabled) async {
    if (busy) return;
    setState(() => busy = true);
    final outcome = await RunTrackerService.setPassiveMonitoring(enabled);
    await _refresh();
    if (!mounted) return;
    setState(() => busy = false);
    _message(switch (outcome) {
      'enabled' => 'Confronto diagnostico attivato per sette giorni.',
      'disabled' =>
        'Confronto diagnostico disattivato. I passi continuano a essere raccolti.',
      'drive_not_configured' =>
        'Collega prima la cartella Drive dagli strumenti avanzati.',
      _ => 'Impossibile cambiare lo stato del confronto diagnostico.',
    });
  }

  void _message(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));

  @override
  Widget build(BuildContext context) {
    final daily = widget.dailyMovement;
    final progress = widget.stepGoal <= 0
        ? 0.0
        : ((daily?.steps ?? 0) / widget.stepGoal).clamp(0.0, 1.0);
    final active = session?.recording ?? false;
    final elapsed = active && session?.startedAt != null
        ? DateTime.now().difference(session!.startedAt!)
        : Duration.zero;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_refresh(), widget.refreshDailyMovement()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _card(
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 68,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 62,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      Text(
                        progress >= 1 ? '★' : '${(progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oggi',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_integer(daily?.steps ?? 0)} / ${_integer(widget.stepGoal)} passi',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_distance(daily?.distanceMeters ?? 0)} · ${(daily?.calories ?? 0).round()} kcal stimate',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (daily != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          daily.bipSteps > daily.phoneSteps
                              ? 'Amazfit ${_integer(daily.bipSteps)} · telefono ${_integer(daily.phoneSteps)}'
                              : 'Telefono ${_integer(daily.phoneSteps)}${daily.bipSteps > 0 ? ' · Amazfit ${_integer(daily.bipSteps)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _collectionLabel(daily),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (daily?.collectionStatus == 'permission_required')
            TextButton(
              onPressed: _enableSteps,
              child: const Text('Abilita conteggio passi'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _editProfile,
              icon: const Icon(Icons.tune),
              label: const Text('Peso e lunghezza del passo'),
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      active
                          ? session?.activityType == 'run'
                                ? 'Corsa in corso'
                                : 'Camminata in corso'
                          : 'Registra attività',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (active)
                      const Icon(Icons.gps_fixed, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  _duration(elapsed),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _metric(
                      'Distanza',
                      _distance(session?.distanceMeters ?? 0),
                    ),
                    _metric('Passi', _integer(session?.steps ?? 0)),
                    _metric(
                      'Passo',
                      _pace(session?.distanceMeters ?? 0, elapsed),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  active
                      ? '${session?.gpsStatus ?? 'Ricerca GPS…'}${(session?.accuracyMeters ?? 0) > 0 ? ' · ±${session!.accuracyMeters.round()} m' : ''}'
                      : 'Il GPS si attiva soltanto durante una sessione.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (active)
                  FilledButton.icon(
                    onPressed: busy ? null : _stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Termina attività'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => _start('walk'),
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('Camminata'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => _start('run'),
                          icon: const Icon(Icons.directions_run),
                          label: const Text('Corsa'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    session?.passiveActive == true
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: const Text('Confronto diagnostico Fit / Drive'),
                  subtitle: Text(
                    '${session?.automaticStatus ?? 'Controllo…'}\nIl conteggio locale continua anche con il confronto spento.',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy || session == null
                      ? null
                      : () => _setPassiveMonitoring(!session!.passiveActive),
                  icon: Icon(
                    session?.passiveActive == true
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                  label: Text(
                    session?.passiveActive == true
                        ? 'Disattiva confronto diagnostico'
                        : 'Attiva confronto diagnostico',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Carica tutti i dati ora'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );

  Widget _metric(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );

  static String _integer(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  static String _distance(double meters) =>
      '${(meters / 1000).toStringAsFixed(2).replaceFirst('.', ',')} km';

  static String _duration(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String _pace(double meters, Duration elapsed) {
    if (meters < 20 || elapsed.inSeconds <= 0) return '— /km';
    final seconds = (elapsed.inSeconds * 1000 / meters).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} /km';
  }
}
