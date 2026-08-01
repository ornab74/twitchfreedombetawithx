import 'package:flutter/material.dart';

final class PulseRing extends StatelessWidget {
  const PulseRing({
    super.key,
    required this.active,
    this.size = 18,
    this.reduceMotion = false,
  });
  final bool active;
  final double size;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.outline;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          value: active ? .72 : 1,
          strokeWidth: 2,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
          strokeCap: StrokeCap.round,
        ),
      ),
    );
  }
}
