import 'dart:io';

abstract final class AppConfig {
  static const String appName = 'Twitch Freedom';
  static const String appVersion = '0.4.1';
  static const String resolverProfileVersion = 'twitch-hls-v1';
  static const String publicTwitchWebClientId =
      'kimne78kx3ncx6brgo4mv6wki5h1ko';

  static final Uri twitchGql = Uri.parse('https://gql.twitch.tv/gql');
  static final Uri twitchHelix = Uri.parse('https://api.twitch.tv/helix');
  static final Uri twitchToken = Uri.parse('https://id.twitch.tv/oauth2/token');
  static final Uri twitchDevice = Uri.parse(
    'https://id.twitch.tv/oauth2/device',
  );
  static final Uri twitchValidate = Uri.parse(
    'https://id.twitch.tv/oauth2/validate',
  );

  static const String playbackAccessTokenHash =
      'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';

  static const String gemmaModelName = 'gemma-4-E2B-it.litertlm';
  static const String gemmaModelRevision =
      '7fa1d78473894f7e736a21d920c3aa80f950c0db';
  static final Uri gemmaModelUrl = Uri.parse(
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
    'resolve/$gemmaModelRevision/$gemmaModelName',
  );
  static const String gemmaModelSha256 =
      'ab7838cdfc8f77e54d8ca45eadceb20452d9f01e4bfade03e5dce27911b27e42';
  static const int gemmaModelExpectedBytes = 2590000000;
  static const int gemmaMaximumBytes = 3200 * 1024 * 1024;
  static Uri get gemmaModelUri => gemmaModelUrl;
  static String get gemmaSha256 => gemmaModelSha256;

  static const String moonshineProfile = 'moonshine-tiny-5s-f32';
  static const String moonshineModelRevision =
      'a003fac69dda9c4f5b360b8b70ea0623f662c215';
  static const String moonshineTokenizerRevision =
      '25052e44b92f2fd4a43bdddad9aea312be9b3805';
  static final Uri moonshineModelUri = Uri.parse(
    'https://huggingface.co/litert-community/moonshine-tiny/resolve/'
    '$moonshineModelRevision/moonshine_tiny_5s_f32.tflite',
  );
  static final Uri moonshineTokenizerUri = Uri.parse(
    'https://huggingface.co/UsefulSensors/moonshine/resolve/'
    '$moonshineTokenizerRevision/ctranslate2/tiny/tokenizer.json',
  );
  static const Duration moonshineWindow = Duration(seconds: 5);
  static const int moonshineMaximumPcmBytes = 16000 * 2 * 6;

  static const int maxSavedStreams = 200;
  static const int maxChatMessagesPerChannel = 1000;
  static const int maxManifestBytes = 4 * 1024 * 1024;
  static const int maxHttpBodyBytes = 8 * 1024 * 1024;
  static const int maxRedirects = 4;
  static const Duration networkTimeout = Duration(seconds: 20);
  static const Duration chatBatchDefault = Duration(minutes: 7);
  static const Duration autoLockDefault = Duration(minutes: 20);

  static const Set<String> trustedPlaybackHostSuffixes = <String>{
    'ttvnw.net',
    'twitchcdn.net',
    'twitch.tv',
  };

  static bool get isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  static final bool constrainedLinuxRendering = () {
    if (!Platform.isLinux) return false;
    final renderer =
        Platform.environment['TWITCH_FREEDOM_RENDERER']?.toLowerCase() ?? '';
    final mesaSoftware = Platform.environment['LIBGL_ALWAYS_SOFTWARE']
        ?.toLowerCase();
    return renderer.contains('cpu-opengl') ||
        renderer.contains('software') ||
        mesaSoftware == '1' ||
        mesaSoftware == 'true';
  }();
  static bool get ffmpegKitSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
  static bool get videoPlayerPreferred =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
