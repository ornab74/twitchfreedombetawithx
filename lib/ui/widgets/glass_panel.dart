import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../theme.dart';

final class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.blur = 18,
    this.elevated = false,
    this.clip = Clip.hardEdge,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final bool elevated;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    final translucentColor = elevated ? tokens.panelElevated : tokens.panel;
    final panelColor = AppConfig.constrainedLinuxRendering
        ? Color.alphaBlend(translucentColor, tokens.canvas).withValues(alpha: 1)
        : translucentColor;
    // BackdropFilter forces a full-surface readback on desktop software
    // rendering. On GTK/Windows this can leave pointer and text invalidations
    // queued until a native resize. The panel remains visually translucent via
    // its color, without making every interaction depend on a compositor
    // readback.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: clip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: tokens.border.withValues(alpha: 0.9)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

final class NeonDivider extends StatelessWidget {
  const NeonDivider({super.key, this.height = 1});
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            scheme.primary.withValues(alpha: 0.8),
            scheme.secondary.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
