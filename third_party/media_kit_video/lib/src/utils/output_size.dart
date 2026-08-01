import 'dart:math' as math;

/// Whether a native video output should follow [scale] instead of a fixed
/// width and height.
bool usesScaledVideoOutput(double scale) =>
    scale.isFinite && scale > 0 && scale != 1.0;

class ScaledVideoOutputSize {
  const ScaledVideoOutputSize(this.width, this.height);

  final int width;
  final int height;
}

/// Applies the native output scale while keeping dimensions valid for a
/// platform texture.
ScaledVideoOutputSize scaledVideoOutputSize({
  required int width,
  required int height,
  required double scale,
}) {
  if (width <= 0 || height <= 0) {
    return const ScaledVideoOutputSize(0, 0);
  }
  final effectiveScale = scale.isFinite && scale > 0 ? scale : 1.0;
  return ScaledVideoOutputSize(
    math.max(1, (width * effectiveScale).round()),
    math.max(1, (height * effectiveScale).round()),
  );
}
