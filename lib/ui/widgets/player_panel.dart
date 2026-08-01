import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'glass_panel.dart';
import 'pulse_ring.dart';

final class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key, required this.controller});
  final AppController controller;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

final class _PlayerPanelState extends State<PlayerPanel> {
  late PlaybackMode _mode;
  late String _quality;
  late ({
    PlaybackHealth health,
    Uri? uri,
    bool playing,
    bool buffering,
    bool native,
    String channel,
  })
  _playbackView;
  late bool _busy;
  Route<void>? _fullscreenRoute;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.controller.selected?.playbackMode ?? PlaybackMode.video;
    _quality =
        widget.controller.selected?.quality ??
        widget.controller.preferences.preferredQuality;
    _playbackView = _readPlaybackView();
    _busy = widget.controller.busy;
    widget.controller.navigationRevision.addListener(_handleNavigationUpdate);
    widget.controller.shellRevision.addListener(_handleShellUpdate);
    widget.controller.playback.addListener(_handlePlaybackUpdate);
  }

  ({
    PlaybackHealth health,
    Uri? uri,
    bool playing,
    bool buffering,
    bool native,
    String channel,
  })
  _readPlaybackView() {
    final playback = widget.controller.playback;
    return (
      health: playback.health,
      uri: playback.variant?.uri,
      playing: playback.playing,
      buffering: playback.buffering,
      native: playback.useNativeVideoPlayer,
      channel: playback.channel,
    );
  }

  void _handleNavigationUpdate() {
    final selected = widget.controller.selected;
    if (!mounted) return;
    setState(() {
      _mode = selected?.playbackMode ?? PlaybackMode.video;
      _quality =
          selected?.quality ?? widget.controller.preferences.preferredQuality;
    });
  }

  void _handleShellUpdate() {
    final next = widget.controller.busy;
    if (!mounted || next == _busy) return;
    setState(() => _busy = next);
  }

  void _handlePlaybackUpdate() {
    final next = _readPlaybackView();
    if (!mounted || next == _playbackView) return;
    setState(() => _playbackView = next);
    if (_fullscreen && next.uri == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _exitFullscreen());
    }
  }

  void _enterFullscreen() {
    if (_fullscreen || !mounted || widget.controller.playback.variant == null) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    late final PageRoute<void> route;
    route = PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder:
          (
            BuildContext routeContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => _FullscreenPlaybackSurface(
            controller: widget.controller,
            onExit: () => Navigator.of(routeContext).maybePop(),
          ),
    );
    setState(() => _fullscreen = true);
    _fullscreenRoute = route;
    unawaited(
      navigator.push<void>(route).whenComplete(() {
        if (_fullscreenRoute == route) _fullscreenRoute = null;
        if (mounted && _fullscreen) setState(() => _fullscreen = false);
      }),
    );
  }

  void _exitFullscreen() {
    final route = _fullscreenRoute;
    if (!_fullscreen && route == null) return;
    final navigator = route?.navigator;
    if (route != null && navigator != null) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    } else if (mounted) {
      setState(() => _fullscreen = false);
    }
  }

  void _toggleFullscreen() =>
      _fullscreen ? _exitFullscreen() : _enterFullscreen();

  @override
  void didUpdateWidget(covariant PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.navigationRevision.removeListener(
      _handleNavigationUpdate,
    );
    oldWidget.controller.shellRevision.removeListener(_handleShellUpdate);
    oldWidget.controller.playback.removeListener(_handlePlaybackUpdate);
    widget.controller.navigationRevision.addListener(_handleNavigationUpdate);
    widget.controller.shellRevision.addListener(_handleShellUpdate);
    widget.controller.playback.addListener(_handlePlaybackUpdate);
    _handleNavigationUpdate();
    _playbackView = _readPlaybackView();
    _busy = widget.controller.busy;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final playback = controller.playback;
    final selected = controller.selected;
    final tokens = freedomTokens(context);
    final active =
        playback.health == PlaybackHealth.healthy ||
        playback.health == PlaybackHealth.buffering ||
        playback.health == PlaybackHealth.recovering;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selected?.displayName ?? 'Select a channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (controller.preferences.showStreamTitles &&
                        (selected?.title.isNotEmpty ?? false))
                      Text(
                        selected!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                );
                final health = <Widget>[
                  PulseRing(
                    active: active,
                    reduceMotion: controller.preferences.reduceMotion,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    _healthLabel(playback.health),
                    style: TextStyle(
                      color: _healthColor(playback.health, tokens),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ];
                final controls = <Widget>[
                  _CompactMenu<PlaybackMode>(
                    value: _mode,
                    values: PlaybackMode.values,
                    labelFor: (PlaybackMode value) => switch (value) {
                      PlaybackMode.video => 'Video',
                      PlaybackMode.audioOnly => 'Audio only',
                    },
                    icon: Icons.live_tv_rounded,
                    onSelected: (PlaybackMode value) =>
                        setState(() => _mode = value),
                  ),
                  const SizedBox(width: 8),
                  _CompactMenu<String>(
                    value: _mode == PlaybackMode.audioOnly
                        ? 'audio_only'
                        : _quality,
                    values: _mode == PlaybackMode.audioOnly
                        ? const <String>['audio_only']
                        : _qualities,
                    labelFor: (String value) => value,
                    icon: Icons.high_quality_rounded,
                    onSelected: _mode == PlaybackMode.audioOnly
                        ? null
                        : (String value) => setState(() => _quality = value),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: selected == null || _busy
                        ? null
                        : () => controller.startPlayback(
                            quality: _quality,
                            mode: _mode,
                          ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Stop playback',
                    onPressed: active ? controller.stopPlayback : null,
                    icon: const Icon(Icons.stop_rounded),
                  ),
                ];
                if (constraints.maxWidth >= 760) {
                  return Row(
                    children: <Widget>[
                      Expanded(child: title),
                      ...health,
                      const SizedBox(width: 14),
                      ...controls,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: title),
                        ...health,
                      ],
                    ),
                    const SizedBox(height: 9),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: Row(children: controls),
                    ),
                  ],
                );
              },
            ),
          ),
          const NeonDivider(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tokens.border),
              ),
              clipBehavior: Clip.hardEdge,
              child: selected == null
                  ? const _EmptyPlayer(
                      icon: Icons.add_to_queue_rounded,
                      title: 'Add a Twitch channel',
                      subtitle:
                          'The app does not preload demos, thumbnails, avatars, or remote images.',
                    )
                  : playback.variant == null
                  ? _EmptyPlayer(
                      icon: Icons.live_tv_rounded,
                      title: selected.displayName,
                      subtitle:
                          'Choose a mode and quality, then start playback.',
                    )
                  : _fullscreen
                  ? const ColoredBox(color: Colors.black)
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _enterFullscreen,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          if (!playback.variant!.audioOnly)
                            _ResizeStableVideoSurface(controller: controller),
                          if (playback.variant!.audioOnly)
                            _AudioOnlySurface(
                              channel: playback.channel,
                              playing: playback.playing,
                            ),
                          Positioned(
                            left: 30,
                            right: 30,
                            bottom: 82,
                            child: _ClosedCaptionOverlay(
                              controller: controller,
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: _OverlayControls(
                              controller: controller,
                              onToggleFullscreen: _toggleFullscreen,
                              fullscreen: false,
                              insets: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          _TelemetryStrip(controller: controller),
        ],
      ),
    );
  }

  Color _healthColor(PlaybackHealth health, FreedomTokens tokens) =>
      switch (health) {
        PlaybackHealth.healthy => tokens.good,
        PlaybackHealth.buffering ||
        PlaybackHealth.recovering ||
        PlaybackHealth.resolving => tokens.warning,
        PlaybackHealth.failed || PlaybackHealth.stopped => tokens.danger,
        PlaybackHealth.idle => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  String _healthLabel(PlaybackHealth health) => switch (health) {
    PlaybackHealth.idle => 'Ready',
    PlaybackHealth.resolving => 'Resolving',
    PlaybackHealth.buffering => 'Buffering',
    PlaybackHealth.healthy => 'Live',
    PlaybackHealth.recovering => 'Recovering',
    PlaybackHealth.stopped => 'Stopped',
    PlaybackHealth.failed => 'Attention',
  };

  @override
  void dispose() {
    final route = _fullscreenRoute;
    _fullscreenRoute = null;
    if (route != null && route.navigator != null) {
      route.navigator!.removeRoute(route);
    }
    widget.controller.navigationRevision.removeListener(
      _handleNavigationUpdate,
    );
    widget.controller.shellRevision.removeListener(_handleShellUpdate);
    widget.controller.playback.removeListener(_handlePlaybackUpdate);
    super.dispose();
  }
}

const List<String> _qualities = <String>[
  '160p',
  '360p',
  '480p',
  '720p',
  '720p60',
  '1080p',
  '1080p60',
  'best',
];

/// Uses a local menu overlay instead of pushing DropdownRoute. On Linux debug
/// builds the route's full-screen transition/semantics pass can stall the main
/// isolate for more than 100 ms, even though this selector has only a few rows.
final class _CompactMenu<T> extends StatelessWidget {
  const _CompactMenu({
    required this.value,
    required this.values,
    required this.labelFor,
    required this.icon,
    required this.onSelected,
  });

  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final IconData icon;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: values
        .map(
          (T item) => MenuItemButton(
            leadingIcon: Icon(
              item == value
                  ? Icons.check_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 17,
            ),
            onPressed: onSelected == null ? null : () => onSelected!(item),
            child: Text(labelFor(item)),
          ),
        )
        .toList(growable: false),
    builder: (BuildContext context, MenuController menu, Widget? child) =>
        OutlinedButton(
          onPressed: onSelected == null
              ? null
              : () => menu.isOpen ? menu.close() : menu.open(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 17),
              const SizedBox(width: 7),
              Text(labelFor(value)),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more_rounded, size: 17),
            ],
          ),
        ),
  );
}

final class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

final class _AudioOnlySurface extends StatelessWidget {
  const _AudioOnlySurface({required this.channel, required this.playing});
  final String channel;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            playing ? Icons.graphic_eq_rounded : Icons.headphones_rounded,
            size: 70,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 15),
          Text(channel, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('Audio-only private playback'),
        ],
      ),
    );
  }
}

final class _OverlayControls extends StatefulWidget {
  const _OverlayControls({
    required this.controller,
    required this.onToggleFullscreen,
    required this.fullscreen,
    required this.insets,
  });
  final AppController controller;
  final VoidCallback onToggleFullscreen;
  final bool fullscreen;
  final EdgeInsets insets;

  @override
  State<_OverlayControls> createState() => _OverlayControlsState();
}

final class _OverlayControlsState extends State<_OverlayControls> {
  late ({bool playing, double volume}) _view;
  Timer? _hideTimer;
  bool _visible = true;
  double _unmutedVolume = 1;

  @override
  void initState() {
    super.initState();
    _view = _readView();
    if (_view.volume > 0) _unmutedVolume = _view.volume;
    widget.controller.playback.addListener(_handlePlayback);
    _scheduleHide();
  }

  ({bool playing, double volume}) _readView() => (
    playing: widget.controller.playback.playing,
    volume: widget.controller.playback.volume,
  );

  void _handlePlayback() {
    final next = _readView();
    if (!mounted || next == _view) return;
    if (next.volume > 0) _unmutedVolume = next.volume;
    setState(() => _view = next);
    _scheduleHide();
  }

  void _reveal() {
    if (!_visible && mounted) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _visible) setState(() => _visible = false);
    });
  }

  void _toggleMute() {
    final playback = widget.controller.playback;
    if (playback.volume > 0) {
      _unmutedVolume = playback.volume;
      unawaited(playback.setVolume(0));
    } else {
      unawaited(playback.setVolume(_unmutedVolume.clamp(.1, 2)));
    }
    _reveal();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.controller.playback;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _reveal(),
      onHover: (_) => _reveal(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reveal(),
        child: Padding(
          padding: widget.insets,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: IgnorePointer(
                ignoring: !_visible,
                child: AnimatedOpacity(
                  key: const ValueKey<String>('twitch-playback-controls'),
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101010),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                              final compact = constraints.maxWidth < 300;
                              return Row(
                                mainAxisSize: MainAxisSize.max,
                                children: <Widget>[
                                  _controlButton(
                                    tooltip: playback.playing
                                        ? 'Pause'
                                        : 'Resume',
                                    onPressed: playback.toggle,
                                    icon: playback.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  _controlButton(
                                    tooltip: playback.volume > 0
                                        ? 'Mute'
                                        : 'Unmute',
                                    onPressed: _toggleMute,
                                    icon: playback.volume > 0
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_off_rounded,
                                  ),
                                  if (!compact) ...<Widget>[
                                    Expanded(
                                      child: Slider(
                                        value: playback.volume,
                                        min: 0,
                                        max: 2,
                                        onChanged: (double value) {
                                          unawaited(playback.setVolume(value));
                                          _reveal();
                                        },
                                      ),
                                    ),
                                    Text(
                                      '${(playback.volume * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                  ] else
                                    const Spacer(),
                                  _controlButton(
                                    tooltip: widget.fullscreen
                                        ? 'Exit full-window playback (Esc)'
                                        : 'Full-window playback (double-click)',
                                    onPressed: widget.onToggleFullscreen,
                                    icon: widget.fullscreen
                                        ? Icons.fullscreen_exit_rounded
                                        : Icons.fullscreen_rounded,
                                  ),
                                ],
                              );
                            },
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

  Widget _controlButton({
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
  }) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 38, height: 38),
    padding: const EdgeInsets.all(6),
    onPressed: () {
      onPressed();
      _reveal();
    },
    icon: Icon(icon, color: Colors.white, size: 22),
  );

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.playback.removeListener(_handlePlayback);
    super.dispose();
  }
}

final class _FullscreenPlaybackSurface extends StatefulWidget {
  const _FullscreenPlaybackSurface({
    required this.controller,
    required this.onExit,
  });

  final AppController controller;
  final VoidCallback onExit;

  @override
  State<_FullscreenPlaybackSurface> createState() =>
      _FullscreenPlaybackSurfaceState();
}

final class _FullscreenPlaybackSurfaceState
    extends State<_FullscreenPlaybackSurface> {
  late ({Uri? uri, bool audioOnly, bool playing}) _view;

  @override
  void initState() {
    super.initState();
    _view = _readView();
    widget.controller.playback.addListener(_handlePlayback);
  }

  ({Uri? uri, bool audioOnly, bool playing}) _readView() {
    final playback = widget.controller.playback;
    return (
      uri: playback.variant?.uri,
      audioOnly: playback.variant?.audioOnly ?? false,
      playing: playback.playing,
    );
  }

  void _handlePlayback() {
    final next = _readView();
    if (!mounted || next == _view) return;
    _view = next;
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.f11)) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.controller.playback;
    return Material(
      color: Colors.black,
      child: SizedBox.expand(
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onExit,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (playback.variant != null && !playback.variant!.audioOnly)
                  _ResizeStableVideoSurface(controller: widget.controller),
                if (playback.variant?.audioOnly ?? false)
                  _AudioOnlySurface(
                    channel: playback.channel,
                    playing: playback.playing,
                  ),
                if (playback.variant == null)
                  const _EmptyPlayer(
                    icon: Icons.live_tv_outlined,
                    title: 'Playback ended',
                    subtitle: 'Press Escape to return.',
                  ),
                Positioned(
                  left: 30,
                  right: 30,
                  bottom: 104,
                  child: SafeArea(
                    top: false,
                    child: _ClosedCaptionOverlay(controller: widget.controller),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 22,
                  child: SafeArea(
                    top: false,
                    child: _OverlayControls(
                      controller: widget.controller,
                      onToggleFullscreen: widget.onExit,
                      fullscreen: true,
                      insets: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.playback.removeListener(_handlePlayback);
    super.dispose();
  }
}

/// Crostini's software OpenGL compositor can keep presenting the previous
/// backing-store size while an external video texture is producing frames.
/// Briefly removing that texture during a metrics transition gives Flutter a
/// cheap black frame at the new size before video painting resumes.
final class _ResizeStableVideoSurface extends StatefulWidget {
  const _ResizeStableVideoSurface({required this.controller});

  final AppController controller;

  @override
  State<_ResizeStableVideoSurface> createState() =>
      _ResizeStableVideoSurfaceState();
}

final class _ResizeStableVideoSurfaceState
    extends State<_ResizeStableVideoSurface>
    with WidgetsBindingObserver {
  Timer? _settleTimer;
  bool _suppressTexture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    _settleTimer?.cancel();
    if (mounted && !_suppressTexture) {
      setState(() => _suppressTexture = true);
    }
    _settleTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _suppressTexture = false);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      Offstage(
        offstage: _suppressTexture,
        child: RepaintBoundary(child: widget.controller.playback.buildVideo()),
      ),
      if (_suppressTexture) const ColoredBox(color: Colors.black),
    ],
  );

  @override
  void dispose() {
    _settleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final class _ClosedCaptionOverlay extends StatelessWidget {
  const _ClosedCaptionOverlay({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: controller.aiRevision,
    builder: (BuildContext context, int revision, Widget? child) {
      final enabled = controller.preferences.ai.closedCaptions;
      final text = controller.speechText.trim();
      if (!enabled || text.isEmpty) return const SizedBox.shrink();
      return IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: 'Closed captions: $text',
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.25,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class _TelemetryStrip extends StatefulWidget {
  const _TelemetryStrip({required this.controller});
  final AppController controller;

  @override
  State<_TelemetryStrip> createState() => _TelemetryStripState();
}

final class _TelemetryStripState extends State<_TelemetryStrip> {
  final List<double> _samples = <double>[];
  Timer? _ticker;
  late ({
    PlaybackHealth health,
    bool playing,
    bool buffering,
    Uri? uri,
    int cacheMiB,
  })
  _view;

  @override
  void initState() {
    super.initState();
    _view = _readView();
    widget.controller.playback.addListener(_handlePlayback);
    _syncTicker();
  }

  ({
    PlaybackHealth health,
    bool playing,
    bool buffering,
    Uri? uri,
    int cacheMiB,
  })
  _readView() {
    final playback = widget.controller.playback;
    return (
      health: playback.health,
      playing: playback.playing,
      buffering: playback.buffering,
      uri: playback.variant?.uri,
      cacheMiB: playback.cachePolicy.maximumMiB,
    );
  }

  void _handlePlayback() {
    final next = _readView();
    if (next == _view) return;
    _view = next;
    _appendSample();
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final playback = widget.controller.playback;
    final active = playback.playing || playback.buffering;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _appendSample();
        if (mounted) setState(() {});
      });
    } else if (!active && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
      _samples.clear();
    }
  }

  void _appendSample() {
    final playback = widget.controller.playback;
    final base = switch (playback.health) {
      PlaybackHealth.healthy => .92,
      PlaybackHealth.buffering => .18,
      PlaybackHealth.recovering => .34,
      PlaybackHealth.resolving => .55,
      PlaybackHealth.failed => .08,
      PlaybackHealth.idle || PlaybackHealth.stopped => .42,
    };
    final phase = (playback.position.inSeconds % 7) * .008;
    _samples.add((base - phase).clamp(.05, .98).toDouble());
    if (_samples.length > 42) _samples.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.controller.playback;
    final variant = playback.variant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: freedomTokens(context).panelElevated.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: freedomTokens(context).border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: <Widget>[
              _Metric(label: 'QUALITY', value: variant?.qualityLabel ?? '—'),
              _Metric(
                label: 'STREAM',
                value: variant == null
                    ? '—'
                    : playback.cachePolicy.lowLatency
                    ? 'HLS • Low latency'
                    : 'HLS • Stable',
              ),
              _Metric(
                label: 'CONNECTION',
                value: _connectionLabel(playback.health),
                valueColor: _connectionColor(context, playback.health),
              ),
              _Metric(label: 'UPTIME', value: _formatDuration(playback.uptime)),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    height: 45,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _ConnectionSparklinePainter(
                                samples: List<double>.of(_samples),
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${playback.constrainedMediaOutput ? 'CPU SAFE • ' : ''}'
                          'RAM ONLY • ${playback.cachePolicy.maximumMiB} MiB',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 9,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                letterSpacing: .45,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _connectionLabel(PlaybackHealth health) => switch (health) {
    PlaybackHealth.healthy => 'Excellent',
    PlaybackHealth.buffering => 'Buffering',
    PlaybackHealth.recovering => 'Recovering',
    PlaybackHealth.resolving => 'Connecting',
    PlaybackHealth.failed => 'Offline',
    PlaybackHealth.idle || PlaybackHealth.stopped => 'Ready',
  };

  Color _connectionColor(BuildContext context, PlaybackHealth health) {
    final tokens = freedomTokens(context);
    return switch (health) {
      PlaybackHealth.healthy => tokens.good,
      PlaybackHealth.buffering ||
      PlaybackHealth.recovering ||
      PlaybackHealth.resolving => tokens.warning,
      PlaybackHealth.failed => tokens.danger,
      PlaybackHealth.idle ||
      PlaybackHealth.stopped => Theme.of(context).colorScheme.onSurface,
    };
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.playback.removeListener(_handlePlayback);
    super.dispose();
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: <Widget>[
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: valueColor),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ConnectionSparklinePainter extends CustomPainter {
  const _ConnectionSparklinePainter({
    required this.samples,
    required this.color,
  });

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = color.withValues(alpha: .16)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height * .65),
      Offset(size.width, size.height * .65),
      baseline,
    );
    if (samples.length < 2) return;
    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      final x = size.width * index / (samples.length - 1);
      final y = size.height * (1 - samples[index]);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionSparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.samples != samples;
}
