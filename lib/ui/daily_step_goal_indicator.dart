import 'dart:math' as math;

import 'package:flutter/material.dart';

class DailyStepGoalIndicator extends StatefulWidget {
  const DailyStepGoalIndicator({
    required this.steps,
    required this.goal,
    required this.onTap,
    super.key,
  });

  final int steps;
  final int goal;
  final VoidCallback onTap;

  @override
  State<DailyStepGoalIndicator> createState() => _DailyStepGoalIndicatorState();
}

class _DailyStepGoalIndicatorState extends State<DailyStepGoalIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController celebration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant DailyStepGoalIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.steps < oldWidget.goal && widget.steps >= widget.goal) {
      celebration.forward(from: 0);
    }
  }

  @override
  void dispose() {
    celebration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.goal <= 0
        ? 0.0
        : (widget.steps / widget.goal).clamp(0.0, 1.0);
    final complete = progress >= 1;
    final label = widget.steps >= 1000
        ? '${(widget.steps / 1000).toStringAsFixed(1)}k'
        : '${widget.steps}';
    return Tooltip(
      message: '${widget.steps} di ${widget.goal} passi',
      child: Semantics(
        button: true,
        label: 'Obiettivo giornaliero: ${widget.steps} di ${widget.goal} passi',
        child: InkResponse(
          onTap: widget.onTap,
          radius: 26,
          child: AnimatedBuilder(
            animation: celebration,
            builder: (context, child) {
              final wave = math.sin(celebration.value * math.pi);
              return Transform.scale(scale: 1 + wave * 0.14, child: child);
            },
            child: SizedBox.square(
              dimension: 42,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CustomPaint(
                  painter: _StepRingPainter(
                    progress: value,
                    complete: complete,
                    colorScheme: Theme.of(context).colorScheme,
                  ),
                  child: Center(
                    child: Text(
                      complete ? '★' : label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: complete
                            ? const Color(0xffb86e00)
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRingPainter extends CustomPainter {
  const _StepRingPainter({
    required this.progress,
    required this.complete,
    required this.colorScheme,
  });

  final double progress;
  final bool complete;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final active = Paint()
      ..color = complete ? const Color(0xffffa000) : colorScheme.primary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      active,
    );
    if (complete) {
      final glow = Paint()
        ..color = const Color(0xffffc107).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, radius + 2, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _StepRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.complete != complete ||
      oldDelegate.colorScheme != colorScheme;
}
