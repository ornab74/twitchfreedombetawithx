import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/models.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import 'linux_ffmpeg_adapter.dart';

String cpuSafePlaybackQuality(String requested) {
  final normalized = requested.trim().toLowerCase();
  if (normalized == 'best' ||
      normalized == 'source' ||
      normalized == '720p60') {
    return '720p';
  }
  final match = RegExp(r'^(\d{3,4})p(?:(\d{2,3}))?$').firstMatch(normalized);
  if (match == null) return requested;
  final height = int.tryParse(match.group(1)!) ?? 0;
  final fps = int.tryParse(match.group(2) ?? '') ?? 30;
  return height > 720 || height == 720 && fps > 30 ? '720p' : requested;
}

/// Cross-platform player centered on media_kit, with video_player retained as a
/// native Apple/Android compatibility backend and a tightly allowlisted system
/// FFmpeg process used only for bounded, ephemeral audio extraction.
final class UnifiedPlaybackController extends ChangeNotifier {
  UnifiedPlaybackController({required SecureLog log})
    : _log = log,
      _systemFfmpeg = SystemFfmpegAdapter(log: log);

  final SecureLog _log;
  final SystemFfmpegAdapter _systemFfmpeg;
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  PlaybackHealth _health = PlaybackHealth.idle;
  StreamVariant? _variant;
  String _channel = '';
  String _error = '';
  bool _playing = false;
  bool _buffering = false;
  bool _backendBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _volumeCommitTimer;
  Timer? _bufferingTimer;
  Uri? _lastUri;
  vp.VideoPlayerController? _nativeController;
  bool _useNativeVideoPlayer = false;
  DateTime? _sessionStartedAt;
  int _bufferingEvents = 0;
  SecureVideoCachePolicy _cachePolicy =
      const SecureVideoCachePolicy.videoLowLatency();
  bool _lowLatency = true;
  VideoAcceleration _videoAcceleration = VideoAcceleration.automatic;

  PlaybackHealth get health => _health;
  StreamVariant? get variant => _variant;
  String get channel => _channel;
  String get error => _error;
  bool get playing => _playing;
  bool get buffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get useNativeVideoPlayer => _useNativeVideoPlayer;
  vp.VideoPlayerController? get nativeVideoController => _nativeController;
  Duration get uptime => _sessionStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_sessionStartedAt!);
  int get bufferingEvents => _bufferingEvents;
  SecureVideoCachePolicy get cachePolicy => _cachePolicy;
  bool get constrainedMediaOutput => _softwareMediaOutput;
  VideoAcceleration get videoAcceleration => _videoAcceleration;

  bool willUseSoftwareOutput(VideoAcceleration acceleration) =>
      acceleration == VideoAcceleration.softwareCpu ||
      (acceleration == VideoAcceleration.automatic &&
          Platform.isLinux &&
          ((Platform.environment['TWITCH_FREEDOM_MEDIA_RENDERER'] ?? '')
                      .toLowerCase() ==
                  'software' ||
              Platform.environment['TWITCH_FREEDOM_HWDEC_AVAILABLE'] == '0'));

  bool get _softwareMediaOutput => willUseSoftwareOutput(_videoAcceleration);

  void _ensureMediaBackend(SecureVideoCachePolicy policy) {
    _cachePolicy = policy;
    if (_player != null) return;
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: PlayerConfiguration(
        title: 'Twitch Freedom',
        bufferSize: policy.maximumBytes,
      ),
    );
    _player = player;
    final softwareRendering = _softwareMediaOutput;
    final highResolution = policy.maximumMiB >= 64;
    _videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !softwareRendering,
        // auto-safe is mpv's FFmpeg-backed zero-copy allowlist. It avoids
        // fragile GPU APIs while still selecting VA-API, NVDEC, or VDPAU when
        // the Linux runner detected an accessible video device.
        hwdec: softwareRendering ? 'no' : 'auto-safe',
        // CPU pixel-buffer transfer at full 1080p can monopolize GTK's raster
        // thread during a maximize/fullscreen resize. Half-scale output keeps
        // the texture responsive while decoding the selected stream normally.
        // A full 1080p EGL texture can saturate an integrated GPU's fill and
        // context-switch budget even while CPU usage remains low. Rendering it
        // at 75% preserves a sharp UI-sized image and gives Flutter headroom
        // to sustain compositor frames. 720p and below remain native size.
        scale: softwareRendering
            ? .5
            : highResolution
            ? .75
            : 1,
      ),
    );
    if (softwareRendering) {
      _log.info(
        'Playback video output configured for CPU pixel-buffer rendering.',
      );
    }
    _bindStreams(player);
  }

  Future<void> _applySecureCachePolicy(
    Player player,
    SecureVideoCachePolicy policy,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    await platform.waitForPlayerInitialization;
    final properties = policy.nativeProperties(
      softwareRendering: _softwareMediaOutput,
    );
    for (final entry in properties.entries) {
      await platform.setProperty(
        entry.key,
        entry.value,
        waitForInitialization: false,
      );
    }
    _log.info(
      'Secure playback cache: RAM-only, bounded to '
      '${policy.maximumBytes ~/ (1024 * 1024)} MiB.',
    );
  }

  void _bindStreams(Player player) {
    _subscriptions.add(
      player.stream.playing.listen((bool value) {
        _playing = value;
        if (value) {
          _buffering = false;
          _setHealth(PlaybackHealth.healthy);
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((bool value) {
        _backendBuffering = value;
        _bufferingTimer?.cancel();
        if (!value) {
          final changed = _buffering;
          _buffering = false;
          if (_playing) _setHealth(PlaybackHealth.healthy);
          if (changed) notifyListeners();
          return;
        }
        final observedPosition = _position;
        _bufferingTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!_backendBuffering || _position != observedPosition) return;
          if (!_buffering) _bufferingEvents += 1;
          _buffering = true;
          _setHealth(PlaybackHealth.buffering);
          notifyListeners();
        });
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((Duration value) {
        // Position can arrive dozens of times per second. It is sampled by
        // telemetry consumers and must not invalidate the Flutter widget tree.
        final advanced = value != _position;
        _position = value;
        if (advanced && _buffering) {
          _buffering = false;
          if (_playing) _setHealth(PlaybackHealth.healthy);
          notifyListeners();
        }
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((Duration value) {
        _duration = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((String value) {
        if (value.trim().isEmpty) return;
        _log.warning('Playback backend: $value');
        // mpv can report recoverable demux/HLS notices after it has already
        // started rendering. Do not show a global error banner for a live
        // session; only recovery exhaustion is a user-visible failure.
        if (!_playing && _health != PlaybackHealth.healthy) {
          _error = value;
          _scheduleRecovery();
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((bool completed) {
        if (completed && _lastUri != null) _scheduleRecovery();
      }),
    );
  }

  Future<AppResult<void>> play({
    required String channel,
    required StreamVariant variant,
    required double volume,
    bool preferNativeBackend = false,
    bool resetRecoveryBudget = true,
    bool lowLatency = true,
    VideoAcceleration acceleration = VideoAcceleration.automatic,
    bool allowAccelerationFallback = true,
  }) async {
    try {
      final accelerationChanged = acceleration != _videoAcceleration;
      await stop(clearIdentity: false, releaseSecureCache: accelerationChanged);
      _videoAcceleration = acceleration;
      _lowLatency = lowLatency;
      final policy = SecureVideoCachePolicy.forStream(
        audioOnly: variant.audioOnly,
        qualityLabel: variant.qualityLabel,
        lowLatency: lowLatency,
      );
      _ensureMediaBackend(policy);
      await _applySecureCachePolicy(_player!, policy);
      final player = _player!;
      _channel = channel;
      _variant = variant;
      _lastUri = variant.uri;
      _error = '';
      if (resetRecoveryBudget) {
        _reconnectAttempt = 0;
        _bufferingEvents = 0;
        _sessionStartedAt = DateTime.now();
      }
      _volume = volume.clamp(0.0, 2.0).toDouble();
      _setHealth(PlaybackHealth.resolving);

      final nativeAllowed =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
      _useNativeVideoPlayer =
          preferNativeBackend && nativeAllowed && !variant.audioOnly;
      if (_useNativeVideoPlayer) {
        final controller = vp.VideoPlayerController.networkUrl(
          variant.uri,
          httpHeaders: const <String, String>{
            'User-Agent': 'TwitchFreedom/0.1',
          },
          videoPlayerOptions: vp.VideoPlayerOptions(mixWithOthers: true),
        );
        _nativeController = controller;
        await controller.initialize();
        await controller.setVolume((_volume / 2).clamp(0.0, 1.0).toDouble());
        await controller.play();
        _playing = true;
        _setHealth(PlaybackHealth.healthy);
      } else {
        await player.setVolume((_volume * 50).clamp(0.0, 100.0).toDouble());
        await player.open(
          Media(
            variant.uri.toString(),
            httpHeaders: const <String, String>{
              'User-Agent': 'Mozilla/5.0 TwitchFreedom/0.1',
              'Referer': 'https://www.twitch.tv/',
            },
            extras: <String, Object?>{
              'channel': channel,
              'quality': variant.qualityLabel,
              'audioOnly': variant.audioOnly,
            },
          ),
          play: true,
        );
      }
      await _setWakelock(enabled: true);
      _log.info('Started ${variant.qualityLabel} playback for $channel.');
      notifyListeners();
      return const AppSuccess<void>(null);
    } catch (cause) {
      final attemptedSoftware = willUseSoftwareOutput(acceleration);
      if (!attemptedSoftware &&
          allowAccelerationFallback &&
          !variant.audioOnly) {
        _log.warning(
          'Accelerated playback failed; retrying with the bounded software '
          'video path: $cause',
        );
        await stop(clearIdentity: false, releaseSecureCache: true);
        return play(
          channel: channel,
          variant: variant,
          volume: volume,
          preferNativeBackend: preferNativeBackend,
          resetRecoveryBudget: resetRecoveryBudget,
          lowLatency: lowLatency,
          acceleration: VideoAcceleration.softwareCpu,
          allowAccelerationFallback: false,
        );
      }
      _setHealth(PlaybackHealth.failed);
      final reason = _safePlaybackReason(cause);
      _error = reason;
      _log.error('Playback start failed: $cause');
      notifyListeners();
      return AppError<void>(
        AppFailure(
          'playback_start_failed',
          'Playback could not be started: $reason',
          cause: cause,
          retryable: true,
        ),
      );
    }
  }

  Future<void> pause() async {
    if (_useNativeVideoPlayer) {
      await _nativeController?.pause();
    } else {
      await _player?.pause();
    }
    _playing = false;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_useNativeVideoPlayer) {
      await _nativeController?.play();
    } else {
      await _player?.play();
    }
    _playing = true;
    notifyListeners();
  }

  Future<void> toggle() => _playing ? pause() : resume();

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 2.0).toDouble();
    notifyListeners();
    _volumeCommitTimer?.cancel();
    _volumeCommitTimer = Timer(const Duration(milliseconds: 32), () {
      unawaited(_commitVolume());
    });
  }

  Future<void> _commitVolume() async {
    _volumeCommitTimer = null;
    if (_useNativeVideoPlayer) {
      await _nativeController?.setVolume(
        (_volume / 2).clamp(0.0, 1.0).toDouble(),
      );
    } else {
      await _player?.setVolume((_volume * 50).clamp(0.0, 100.0).toDouble());
    }
  }

  Future<void> stop({
    bool clearIdentity = true,
    bool releaseSecureCache = true,
  }) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _volumeCommitTimer?.cancel();
    _volumeCommitTimer = null;
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _backendBuffering = false;
    final native = _nativeController;
    _nativeController = null;
    if (native != null) {
      await native.pause();
      await native.dispose();
    }
    await _player?.stop();
    if (releaseSecureCache) await _releaseMediaBackend();
    await _setWakelock(enabled: false);
    _playing = false;
    _buffering = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _useNativeVideoPlayer = false;
    _setHealth(PlaybackHealth.idle);
    if (clearIdentity) {
      _channel = '';
      _variant = null;
      _lastUri = null;
      _error = '';
      _sessionStartedAt = null;
      _bufferingEvents = 0;
    }
    notifyListeners();
  }

  void _scheduleRecovery() {
    if (_lastUri == null || _reconnectTimer != null) return;
    if (_reconnectAttempt >= 12) {
      _setHealth(PlaybackHealth.failed);
      _error = 'Playback recovery limit reached.';
      notifyListeners();
      return;
    }
    _reconnectAttempt += 1;
    final seconds = (1 << (_reconnectAttempt - 1)).clamp(1, 30).toInt();
    _setHealth(PlaybackHealth.recovering);
    notifyListeners();
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      final current = _variant;
      if (current == null) return;
      await play(
        channel: _channel,
        variant: current,
        volume: _volume,
        preferNativeBackend: _useNativeVideoPlayer,
        resetRecoveryBudget: false,
        lowLatency: _lowLatency,
        acceleration: _videoAcceleration,
        allowAccelerationFallback: false,
      );
    });
  }

  String _safePlaybackReason(Object cause) {
    var value = cause.toString().replaceAll(
      RegExp(r'https://[^\s\]\)]+', caseSensitive: false),
      '[media URL]',
    );
    value = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (value.length > 220) value = '${value.substring(0, 217)}…';
    return value.isEmpty ? 'the media backend returned no details' : value;
  }

  Future<void> _setWakelock({required bool enabled}) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (cause) {
      // Crostini commonly has no org.freedesktop.portal.Desktop service.
      // Preventing screen sleep is optional and must never stop playback.
      _log.warning(
        'Desktop wakelock unavailable; playback will continue: $cause',
      );
    }
  }

  void _setHealth(PlaybackHealth value) {
    if (_health == value) return;
    _health = value;
  }

  Future<void> _releaseMediaBackend() async {
    final subscriptions = List<StreamSubscription<Object?>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) await player.dispose();
  }

  /// Creates a short 16 kHz mono PCM file for local speech recognition. The
  /// caller must delete it immediately after transcription.
  Future<AppResult<File>> captureSpeechWindow({
    Duration duration = const Duration(seconds: 5),
  }) async {
    final uri = _lastUri;
    if (uri == null) {
      return const AppError<File>(
        AppFailure(
          'no_stream',
          'Start a stream before capturing speech context.',
        ),
      );
    }
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return const AppError<File>(
        AppFailure(
          'desktop_ffmpeg_unavailable',
          'Streamer-audio extraction currently uses the secure desktop system-FFmpeg backend.',
        ),
      );
    }

    try {
      final temp = await getTemporaryDirectory();
      final file = File(
        p.join(
          temp.path,
          'tf_speech_${DateTime.now().microsecondsSinceEpoch}.s16le',
        ),
      );
      return _systemFfmpeg.extractPcm(
        input: uri,
        output: file,
        duration: duration,
      );
    } catch (cause) {
      _log.warning('Speech audio tap failed: $cause');
      return AppError<File>(
        AppFailure(
          'audio_tap_failed',
          'Could not create a local speech window.',
          cause: cause,
          retryable: true,
        ),
      );
    }
  }

  Widget buildVideo({BoxFit fit = BoxFit.contain}) {
    final native = _nativeController;
    if (_useNativeVideoPlayer && native != null && native.value.isInitialized) {
      return vp.VideoPlayer(native);
    }
    final controller = _videoController;
    // A stream restart can preserve the old variant while the old native
    // backend is being disposed and its replacement is being created. Keep
    // that one-frame transition black instead of force-unwrapping a controller
    // which is deliberately null during teardown.
    if (controller == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return Video(
      controller: controller,
      fit: fit,
      controls: null,
      wakelock: true,
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _volumeCommitTimer?.cancel();
    _bufferingTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_nativeController?.dispose());
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}

/// A deliberately memory-only cache policy for expiring HLS manifests and
/// signed video segments. The public model is useful for telemetry and tests;
/// the native backend receives the actual enforcement properties.
@immutable
final class SecureVideoCachePolicy {
  const SecureVideoCachePolicy({
    required this.maximumBytes,
    required this.readahead,
    required this.lowLatency,
  });

  const SecureVideoCachePolicy.videoLowLatency()
    : maximumBytes = 48 * 1024 * 1024,
      readahead = const Duration(milliseconds: 1500),
      lowLatency = true;

  final int maximumBytes;
  final Duration readahead;
  final bool lowLatency;

  int get maximumMiB => maximumBytes ~/ (1024 * 1024);

  Map<String, String> nativeProperties({required bool softwareRendering}) =>
      <String, String>{
        // media_kit defaults this to `yes`. Twitch manifests and signed
        // segment URLs must never be persisted in mpv's on-disk cache.
        'cache-on-disk': 'no',
        'cache': 'yes',
        'demuxer-max-bytes': maximumBytes.toString(),
        // A live stream has no useful rewind history. Keeping this at zero
        // bounds memory and removes stale signed media from RAM sooner.
        'demuxer-max-back-bytes': '0',
        'demuxer-readahead-secs': (readahead.inMilliseconds / 1000)
            .toStringAsFixed(2),
        'cache-pause': 'no',
        if (softwareRendering) ...<String, String>{
          // Enforce this at mpv level as well as VideoController level so
          // FFmpeg never probes VAAPI/VDPAU in Crostini.
          'hwdec': 'no',
          'vd-lavc-dr': 'no',
          // Reserve CPU capacity for Flutter/GTK and local inference instead
          // of letting FFmpeg spawn a decoder worker for every logical core.
          'vd-lavc-threads': '3',
        } else ...<String, String>{
          'hwdec': 'auto-safe',
          'vd-lavc-dr': 'yes',
          // Favor stable frame delivery over costly high-order GPU shaders.
          // Flutter displays the result inside a resizable panel, where these
          // fast filters are visually appropriate and substantially cheaper.
          'scale': 'bilinear',
          'cscale': 'bilinear',
          'dscale': 'bilinear',
          'deband': 'no',
          'interpolation': 'no',
        },
      };

  factory SecureVideoCachePolicy.forStream({
    required bool audioOnly,
    required String qualityLabel,
    required bool lowLatency,
  }) {
    final quality = qualityLabel.toLowerCase();
    final int mebibytes = audioOnly
        ? 12
        : quality.contains('1080') || quality == 'best'
        ? 64
        : quality.contains('720')
        ? 48
        : 32;
    return SecureVideoCachePolicy(
      maximumBytes: mebibytes * 1024 * 1024,
      readahead: lowLatency
          ? const Duration(milliseconds: 1500)
          : const Duration(seconds: 5),
      lowLatency: lowLatency,
    );
  }
}
