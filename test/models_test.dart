import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/app_config.dart';
import 'package:twitch_freedom_ultra/core/models.dart';

void main() {
  test('stream live status can be explicitly reset to unknown', () {
    final now = DateTime.utc(2026);
    final stream = StreamRecord(
      id: 'stream-1',
      channel: 'example',
      displayName: 'Example',
      url: Uri.https('www.twitch.tv', '/example'),
      title: '',
      category: '',
      language: 'en',
      playbackMode: PlaybackMode.video,
      quality: 'best',
      volume: 1,
      createdAt: now,
      updatedAt: now,
      playCount: 0,
      online: true,
    );

    expect(stream.copyWith().online, isTrue);
    expect(stream.copyWith(online: null).online, isNull);
    expect(stream.copyWith(online: false).online, isFalse);
  });

  test('Gemma artifact pin uses immutable revision and matching digest', () {
    expect(
      AppConfig.gemmaModelUri.path,
      contains(AppConfig.gemmaModelRevision),
    );
    expect(
      AppConfig.gemmaSha256,
      'ab7838cdfc8f77e54d8ca45eadceb20452d9f01e4bfade03e5dce27911b27e42',
    );
  });

  test('preferences round-trip all feature flags', () {
    const original = AppPreferences(
      theme: ThemeProfile.oledVoid,
      drawerOpen: false,
      showStreamTitles: false,
      reduceMotion: true,
      autoLockMinutes: 5,
      preferredQuality: '1080p60',
      videoAcceleration: VideoAcceleration.hardwareGpu,
      ai: AiFeatureSettings(
        enabled: true,
        moodColoring: true,
        protectiveMode: ProtectiveMode.mirror,
        jokeMode: true,
        technicalCompanion: true,
        calmingComposer: true,
        speechContext: true,
        closedCaptions: true,
        retainTranscripts: true,
        memoryEnabled: true,
        batchMinutes: 9,
        safetySensitivity: .82,
        backend: AiBackend.cpuOnly,
        modelDirectory: '/models/gemma',
        autoLoadModel: false,
      ),
    );
    final restored = AppPreferences.fromJson(original.toJson());
    expect(restored.theme, ThemeProfile.oledVoid);
    expect(restored.drawerOpen, isFalse);
    expect(restored.videoAcceleration, VideoAcceleration.hardwareGpu);
    expect(restored.ai.protectiveMode, ProtectiveMode.mirror);
    expect(restored.ai.batchMinutes, 9);
    expect(restored.ai.safetySensitivity, closeTo(.82, .0001));
    expect(restored.ai.modelDirectory, '/models/gemma');
    expect(restored.ai.autoLoadModel, isFalse);
    expect(restored.ai.closedCaptions, isTrue);
    expect(restored.ai.retainTranscripts, isTrue);
  });

  test('chat canonical text stays separate from protective mirror text', () {
    final message = ChatMessage(
      id: 'm1',
      channel: 'channel',
      user: 'user',
      text: 'canonical original',
      timestamp: DateTime.utc(2026),
      tags: const <String, String>{},
    ).copyWith(softenedText: 'AI softened alternative', harmConfidence: .9);
    expect(message.text, 'canonical original');
    expect(message.softenedText, 'AI softened alternative');
    expect(message.potentiallyHarmful, isTrue);
  });

  test('discovery preference copyWith preserves untouched fields', () {
    const original = DiscoveryPreference(
      categories: <String>['Science & Technology'],
      languages: <String>['en'],
      excludedChannels: <String>['blocked_channel'],
      technicalWeight: .8,
      preferLowResource: true,
    );
    final changed = original.copyWith(
      categories: <String>['Software and Game Development'],
    );
    expect(changed.categories, <String>['Software and Game Development']);
    expect(changed.languages, <String>['en']);
    expect(changed.excludedChannels, <String>['blocked_channel']);
    expect(changed.technicalWeight, closeTo(.8, .0001));
    expect(changed.preferLowResource, isTrue);
  });
}
