import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../x/x_media_store.dart';

final class XSecureImage extends StatefulWidget {
  const XSecureImage({
    super.key,
    required this.uri,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final Uri uri;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  State<XSecureImage> createState() => _XSecureImageState();
}

final class _XSecureImageState extends State<XSecureImage> {
  NetworkImage? _provider;

  @override
  void initState() {
    super.initState();
    if (XMediaStore.isTrustedMediaUri(widget.uri)) {
      _provider = NetworkImage(widget.uri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Image(
        image: provider,
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, sync) => frame != null || sync
            ? child
            : const ColoredBox(
                color: Colors.black12,
                child: Center(child: CircularProgressIndicator()),
              ),
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black12,
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final provider = _provider;
    if (provider != null) unawaited(provider.evict());
    super.dispose();
  }
}

final class XSecureVideo extends StatefulWidget {
  const XSecureVideo({
    super.key,
    required this.uri,
    this.posterUri,
    this.onPlaybackChanged,
  });
  final Uri uri;
  final Uri? posterUri;
  final ValueChanged<bool>? onPlaybackChanged;

  @override
  State<XSecureVideo> createState() => _XSecureVideoState();
}

final class _XSecureVideoState extends State<XSecureVideo> {
  Player? _player;
  VideoController? _controller;
  bool _starting = false;
  StreamSubscription<bool>? _playingSubscription;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Colors.black),
          if (widget.posterUri case final poster?)
            Opacity(opacity: .72, child: XSecureImage(uri: poster)),
          Center(
            child: IconButton.filled(
              onPressed: _starting ? null : _start,
              icon: _starting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play video',
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 8,
            child: Chip(
              avatar: Icon(Icons.movie_rounded, size: 16),
              label: Text('Video'),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      );
    }
    return Video(controller: controller, fit: BoxFit.contain, wakelock: false);
  }

  Future<void> _start() async {
    if (!XMediaStore.isTrustedMediaUri(widget.uri)) return;
    setState(() => _starting = true);
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Twitch Freedom X media',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    final controller = VideoController(player);
    _playingSubscription = player.stream.playing.listen(
      (playing) => widget.onPlaybackChanged?.call(playing),
    );
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.waitForPlayerInitialization;
      const properties = <String, String>{
        'cache-on-disk': 'no',
        'cache': 'yes',
        'demuxer-max-bytes': '${64 * 1024 * 1024}',
        'demuxer-max-back-bytes': '${8 * 1024 * 1024}',
        'demuxer-readahead-secs': '12',
        'cache-pause': 'yes',
        'cache-pause-initial': 'yes',
        'hwdec': 'auto-safe',
      };
      for (final entry in properties.entries) {
        await platform.setProperty(
          entry.key,
          entry.value,
          waitForInitialization: false,
        );
      }
    }
    try {
      await player.open(Media(widget.uri.toString()), play: true);
    } catch (_) {
      await player.dispose();
      await _playingSubscription?.cancel();
      _playingSubscription = null;
      if (mounted) setState(() => _starting = false);
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _controller = controller;
      _starting = false;
    });
  }

  @override
  void dispose() {
    final player = _player;
    unawaited(_playingSubscription?.cancel());
    widget.onPlaybackChanged?.call(false);
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
