import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/utils/output_size.dart';
import 'package:twitch_freedom_ultra/core/secure_log.dart';
import 'package:twitch_freedom_ultra/playback/playback_controller.dart';

void main() {
  test('secure playback cache scales within strict RAM bounds', () {
    final audio = SecureVideoCachePolicy.forStream(
      audioOnly: true,
      qualityLabel: 'audio_only',
      lowLatency: true,
    );
    final standard = SecureVideoCachePolicy.forStream(
      audioOnly: false,
      qualityLabel: '720p60',
      lowLatency: true,
    );
    final high = SecureVideoCachePolicy.forStream(
      audioOnly: false,
      qualityLabel: '1080p60',
      lowLatency: false,
    );

    expect(audio.maximumMiB, 12);
    expect(standard.maximumMiB, 48);
    expect(high.maximumMiB, 64);
    expect(standard.readahead, const Duration(milliseconds: 1500));
    expect(high.readahead, const Duration(seconds: 5));
    final native = standard.nativeProperties(softwareRendering: true);
    expect(native['cache-on-disk'], 'no');
    expect(native['demuxer-max-back-bytes'], '0');
    expect(native['hwdec'], 'no');
    expect(native['vd-lavc-threads'], '3');
    expect(native['vd-lavc-fast'], 'yes');
    expect(native['vd-lavc-skiploopfilter'], 'nonref');
    expect(native['volume-max'], '400');
    expect(native.containsKey('framedrop'), isFalse);
    expect(native.containsKey('video-sync'), isFalse);
    expect(native['scale'], 'bilinear');
    expect(native['gpu-dumb-mode'], 'yes');

    final automaticFallback = standard.nativeProperties(
      softwareRendering: false,
    );
    expect(automaticFallback['hwdec'], 'auto-safe');
    expect(automaticFallback['vd-lavc-threads'], '4');
    expect(automaticFallback['vd-lavc-fast'], 'yes');
    expect(automaticFallback.containsKey('framedrop'), isFalse);
  });

  test('software video output caps expensive resolutions and frame rates', () {
    expect(cpuSafePlaybackQuality('best'), '480p60');
    expect(cpuSafePlaybackQuality('1080p60'), '480p60');
    expect(cpuSafePlaybackQuality('720p60'), '480p60');
    expect(cpuSafePlaybackQuality('720p'), '480p');
    expect(cpuSafePlaybackQuality('480p'), '480p');
    expect(cpuSafePlaybackQuality('audio_only'), 'audio_only');
    expect(cpuSafePlaybackQuality('best', maximumHeight: 360), '360p60');
  });

  test('software texture scaling reduces native pixel transfer dimensions', () {
    final fullHd = scaledVideoOutputSize(width: 1920, height: 1080, scale: .5);
    expect((fullHd.width, fullHd.height), (960, 540));
    final low = scaledVideoOutputSize(width: 568, height: 320, scale: .5);
    expect((low.width, low.height), (284, 160));
    final invalidScale = scaledVideoOutputSize(
      width: 1280,
      height: 720,
      scale: 0,
    );
    expect((invalidScale.width, invalidScale.height), (1280, 720));
    expect(usesScaledVideoOutput(.5), isTrue);
    expect(usesScaledVideoOutput(1), isFalse);
  });

  testWidgets('video surface stays safe while its backend is being replaced', (
    WidgetTester tester,
  ) async {
    final controller = UnifiedPlaybackController(log: SecureLog());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: controller.buildVideo(),
      ),
    );

    expect(find.byType(ColoredBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
