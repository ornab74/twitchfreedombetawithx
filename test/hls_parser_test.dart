import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/models.dart';
import 'package:twitch_freedom_ultra/core/result.dart';
import 'package:twitch_freedom_ultra/twitch/hls_parser.dart';

void main() {
  const parser = HlsMasterParser();
  final base = Uri.parse('https://video-edge.ttvnw.net/master.m3u8');

  test('parses audio, 30 FPS, and exact 60 FPS variants', () {
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=128000,VIDEO="audio_only",NAME="audio_only",CODECS="mp4a.40.2"
audio/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1300000,RESOLUTION=1280x720,FRAME-RATE=30.000,NAME="720p30",CODECS="avc1.4D401F,mp4a.40.2"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,NAME="1080p60",CODECS="avc1.64002A,mp4a.40.2"
1080/index.m3u8
''';
    final result = parser.parse(manifest, base);
    expect(result, isA<AppSuccess<List<StreamVariant>>>());
    final variants = (result as AppSuccess<List<StreamVariant>>).value;
    expect(variants.length, 3);
    expect(selectVariant(variants, 'audio_only')?.audioOnly, isTrue);
    expect(selectVariant(variants, '1080p60')?.fps, 60);
    expect(selectVariant(variants, 'best')?.qualityLabel, '1080p60');
    expect(selectCpuSafeVariant(variants, '720p')?.qualityLabel, '720p');
  });

  test('CPU-safe selection prefers 30 FPS over a 720p60 rendition', () {
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1100000,RESOLUTION=852x480,FRAME-RATE=30.000,NAME="480p"
480/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=60.000,NAME="720p60"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60.000,NAME="1080p60"
1080/index.m3u8
''';
    final result =
        parser.parse(manifest, base) as AppSuccess<List<StreamVariant>>;

    expect(selectCpuSafeVariant(result.value, '720p')?.qualityLabel, '480p');
  });

  test('rejects non-HLS content', () {
    final result = parser.parse('<html>not a manifest</html>', base);
    expect(result, isA<AppError<List<StreamVariant>>>());
  });

  test('rejects a manifest variant that escapes trusted Twitch CDN hosts', () {
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360,FRAME-RATE=30
https://attacker.invalid/steal.m3u8
''';
    final result = parser.parse(manifest, base);
    expect(result, isA<AppError<List<StreamVariant>>>());
  });

  test('resolves relative variant URLs safely', () {
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360,FRAME-RATE=30
variants/360.m3u8
''';
    final result =
        parser.parse(manifest, base) as AppSuccess<List<StreamVariant>>;
    expect(
      result.value.single.uri.toString(),
      'https://video-edge.ttvnw.net/variants/360.m3u8',
    );
  });

  test('accepts a trusted direct media playlist as adaptive source', () {
    const media = '''#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000,
segment.ts
''';
    final result = parser.parse(media, base);
    expect(result, isA<AppSuccess<List<StreamVariant>>>());
    final variants = (result as AppSuccess<List<StreamVariant>>).value;
    expect(variants.single.qualityLabel, 'source');
    expect(variants.single.uri, base);
  });

  test('discovers a variant with harmless tags before its URI', () {
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=852x480,FRAME-RATE=30
#EXT-X-TWITCH-PREFETCH:hint
480/index.m3u8
''';
    final result = parser.parse(manifest, base);
    expect(result, isA<AppSuccess<List<StreamVariant>>>());
    expect(
      (result as AppSuccess<List<StreamVariant>>).value.single.qualityLabel,
      '480p',
    );
  });

  test('fallbacks preserve requested type then portable renditions', () {
    final variants = <StreamVariant>[
      StreamVariant(
        name: 'audio_only',
        uri: base.resolve('audio.m3u8'),
        bandwidth: 128000,
        height: null,
        frameRate: null,
        audioOnly: true,
        codecs: 'mp4a.40.2',
      ),
      StreamVariant(
        name: '480p',
        uri: base.resolve('480.m3u8'),
        bandwidth: 1000000,
        height: 480,
        frameRate: 30,
        audioOnly: false,
        codecs: 'avc1.4D401F,mp4a.40.2',
      ),
    ];
    expect(
      playbackVariantFallbacks(
        variants,
        requested: 'audio_only',
        cpuSafe: true,
      ).first.audioOnly,
      isTrue,
    );
    expect(
      playbackVariantFallbacks(
        variants,
        requested: '480p',
        cpuSafe: true,
      ).first.audioOnly,
      isFalse,
    );
  });
}
