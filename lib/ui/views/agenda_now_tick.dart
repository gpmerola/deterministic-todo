import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds only [builder] (the current-time line) at each new minute, not
/// the day or week grid around it.
///
/// One timer is armed for the next minute boundary while the app is in the
/// foreground; in background it is cancelled, and returning to the
/// foreground re-reads the clock at once. Timers of a suspended process fire
/// late, so the resume read is what keeps the line right after the screen
/// was locked. A change of day is handled by the views' `today`.
class AgendaNowTick extends StatefulWidget {
  const AgendaNowTick({required this.now, required this.builder, super.key});

  final DateTime Function() now;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<AgendaNowTick> createState() => _AgendaNowTickState();
}

class _AgendaNowTickState extends State<AgendaNowTick>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final now = widget.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(next.difference(now) + const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_timer != null) return; // Only `inactive`: still current.
        setState(() {});
        _arm();
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.now());
}
