import 'dart:math' as math;

import 'package:flutter/material.dart';

final class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandPainter(
          primary: scheme.primary,
          secondary: scheme.secondary,
        ),
      ),
    );
  }
}

final class _BrandPainter extends CustomPainter {
  const _BrandPainter({required this.primary, required this.secondary});
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi / 4);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.62,
      height: size.height * 0.62,
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[primary, secondary],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.12)),
      paint,
    );
    final cut = Paint()
      ..color = ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? Colors.black54
          : Colors.white54;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.09, -size.height * 0.09),
          width: size.width * 0.24,
          height: size.height * 0.24,
        ),
        Radius.circular(size.width * 0.05),
      ),
      cut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}
