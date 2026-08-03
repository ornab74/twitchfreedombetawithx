import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_controller.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'unlock_screen.dart';

final class TwitchFreedomApp extends StatefulWidget {
  const TwitchFreedomApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<TwitchFreedomApp> createState() => _TwitchFreedomAppState();
}

final class _TwitchFreedomAppState extends State<TwitchFreedomApp> {
  late ThemeProfile _theme;

  @override
  void initState() {
    super.initState();
    _theme = widget.controller.preferences.theme;
    widget.controller.preferencesRevision.addListener(_handlePreferences);
    widget.controller.bootstrap();
  }

  void _handlePreferences() {
    final next = widget.controller.preferences.theme;
    if (!mounted || next == _theme) return;
    setState(() => _theme = next);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // Keep MaterialApp and the platform surface stable. Controller updates
    // are frequent (typing, chat, playback, scheduler telemetry); rebuilding
    // MaterialApp replaces the root render surface and can defer its frame
    // until the next native resize.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Twitch Freedom',
      theme: FreedomTheme.fromProfile(_theme),
      themeAnimationDuration: Duration.zero,
      home: _AppSurface(controller: controller),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: .85, maxScaleFactor: 2.2),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.preferencesRevision.removeListener(_handlePreferences);
    widget.controller.dispose();
    super.dispose();
  }
}

final class _AppSurface extends StatefulWidget {
  const _AppSurface({required this.controller});
  final AppController controller;

  @override
  State<_AppSurface> createState() => _AppSurfaceState();
}

final class _AppSurfaceState extends State<_AppSurface> {
  late ({bool unlocked, ThemeProfile theme}) _view;

  @override
  void initState() {
    super.initState();
    _view = _readView();
    widget.controller.addListener(_handleControllerChange);
  }

  ({bool unlocked, ThemeProfile theme}) _readView() => (
    unlocked: widget.controller.unlocked,
    theme: widget.controller.preferences.theme,
  );

  void _handleControllerChange() {
    final next = _readView();
    if (next == _view || !mounted) return;
    setState(() => _view = next);
  }

  @override
  void didUpdateWidget(covariant _AppSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    widget.controller.addListener(_handleControllerChange);
    _view = _readView();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: FreedomTheme.fromProfile(_view.theme),
    child: _view.unlocked
        ? HomeScreen(controller: widget.controller)
        : UnlockScreen(controller: widget.controller),
  );

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }
}
