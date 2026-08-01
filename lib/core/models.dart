import 'dart:convert';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:flutter/material.dart' show ColorScheme;

enum PlaybackMode { audioOnly, video }

enum VideoAcceleration { automatic, hardwareGpu, softwareCpu }

enum PlaybackHealth {
  idle,
  resolving,
  buffering,
  healthy,
  recovering,
  stopped,
  failed,
}

enum ThemeProfile {
  obsidianGlass,
  auroraViolet,
  solarGraphite,
  arcticSignal,
  oledVoid,
  highContrast,
  matrix,
  barbie,
  halo2,
  synthwaveSunset,
  oceanAbyss,
  forestTerminal,
  crimsonProtocol,
  desertDusk,
  lunarIce,
  retroArcade,
  royalAmethyst,
  copperSteampunk,
  sakuraNight,
}

enum MoodLabel {
  supportive,
  joyful,
  curious,
  technical,
  neutral,
  tense,
  sarcastic,
  sad,
  hostile,
  uncertain,
}

enum ProtectiveMode { raw, dim, blur, mirror, hideHighConfidence }

enum AgentRole { mood, safety, joke, technical, calming, discovery, summary }

enum AiBackend { gpuFirst, gpuOnly, cpuOnly, npu }

@immutable
final class StreamRecord {
  const StreamRecord({
    required this.id,
    required this.channel,
    required this.displayName,
    required this.url,
    required this.title,
    required this.category,
    required this.language,
    required this.playbackMode,
    required this.quality,
    required this.volume,
    required this.createdAt,
    required this.updatedAt,
    required this.playCount,
    this.lastPlayedAt,
    this.online,
  });

  final String id;
  final String channel;
  final String displayName;
  final Uri url;
  final String title;
  final String category;
  final String language;
  final PlaybackMode playbackMode;
  final String quality;
  final double volume;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPlayedAt;
  final int playCount;
  final bool? online;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'channel': channel,
    'displayName': displayName,
    'url': url.toString(),
    'title': title,
    'category': category,
    'language': language,
    'playbackMode': playbackMode.name,
    'quality': quality,
    'volume': volume,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toUtc().toIso8601String(),
    'playCount': playCount,
    'online': online,
  };

  static StreamRecord fromJson(Map<String, Object?> json) => StreamRecord(
    id: json['id']! as String,
    channel: json['channel']! as String,
    displayName: (json['displayName'] as String?) ?? json['channel']! as String,
    url: Uri.parse(json['url']! as String),
    title: (json['title'] as String?) ?? '',
    category: (json['category'] as String?) ?? '',
    language: (json['language'] as String?) ?? '',
    playbackMode: PlaybackMode.values.byName(
      (json['playbackMode'] as String?) ?? 'video',
    ),
    quality: (json['quality'] as String?) ?? 'best',
    volume: (json['volume'] as num?)?.toDouble() ?? 1,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    lastPlayedAt: json['lastPlayedAt'] == null
        ? null
        : DateTime.parse(json['lastPlayedAt']! as String),
    playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    online: json['online'] as bool?,
  );

  StreamRecord copyWith({
    String? displayName,
    String? title,
    String? category,
    String? language,
    PlaybackMode? playbackMode,
    String? quality,
    double? volume,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    int? playCount,
    bool? online,
  }) => StreamRecord(
    id: id,
    channel: channel,
    displayName: displayName ?? this.displayName,
    url: url,
    title: title ?? this.title,
    category: category ?? this.category,
    language: language ?? this.language,
    playbackMode: playbackMode ?? this.playbackMode,
    quality: quality ?? this.quality,
    volume: volume ?? this.volume,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    playCount: playCount ?? this.playCount,
    online: online ?? this.online,
  );
}

@immutable
final class StreamVariant {
  const StreamVariant({
    required this.name,
    required this.uri,
    required this.bandwidth,
    required this.height,
    required this.frameRate,
    required this.audioOnly,
    required this.codecs,
  });

  final String name;
  final Uri uri;
  final int bandwidth;
  final int? height;
  final double? frameRate;
  final bool audioOnly;
  final String codecs;

  int get fps => frameRate?.round() ?? 30;
  String get qualityLabel =>
      audioOnly ? 'audio_only' : '${height ?? 0}p${fps >= 50 ? fps : ''}';
}

@immutable
final class ResolvedStream {
  const ResolvedStream({
    required this.channel,
    required this.masterUri,
    required this.variants,
    required this.expiresAt,
  });
  final String channel;
  final Uri masterUri;
  final List<StreamVariant> variants;
  final DateTime expiresAt;
}

@immutable
final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channel,
    required this.user,
    required this.text,
    required this.timestamp,
    required this.tags,
    this.mood = MoodLabel.neutral,
    this.moodConfidence = 0,
    this.harmConfidence = 0,
    this.harmReason = '',
    this.softenedText,
    this.isOwn = false,
    this.isModerator = false,
  });

  final String id;
  final String channel;
  final String user;
  final String text;
  final DateTime timestamp;
  final Map<String, String> tags;
  final MoodLabel mood;
  final double moodConfidence;
  final double harmConfidence;
  final String harmReason;
  final String? softenedText;
  final bool isOwn;
  final bool isModerator;

  bool get potentiallyHarmful => harmConfidence >= 0.65;

  ChatMessage copyWith({
    MoodLabel? mood,
    double? moodConfidence,
    double? harmConfidence,
    String? harmReason,
    String? softenedText,
  }) => ChatMessage(
    id: id,
    channel: channel,
    user: user,
    text: text,
    timestamp: timestamp,
    tags: tags,
    mood: mood ?? this.mood,
    moodConfidence: moodConfidence ?? this.moodConfidence,
    harmConfidence: harmConfidence ?? this.harmConfidence,
    harmReason: harmReason ?? this.harmReason,
    softenedText: softenedText ?? this.softenedText,
    isOwn: isOwn,
    isModerator: isModerator,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'channel': channel,
    'user': user,
    'text': text,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'tags': tags,
    'mood': mood.name,
    'moodConfidence': moodConfidence,
    'harmConfidence': harmConfidence,
    'harmReason': harmReason,
    'softenedText': softenedText,
    'isOwn': isOwn,
    'isModerator': isModerator,
  };

  static ChatMessage fromJson(Map<String, Object?> json) => ChatMessage(
    id: json['id']! as String,
    channel: json['channel']! as String,
    user: json['user']! as String,
    text: json['text']! as String,
    timestamp: DateTime.parse(json['timestamp']! as String),
    tags: Map<String, String>.from(
      (json['tags'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
    ),
    mood: MoodLabel.values.byName((json['mood'] as String?) ?? 'neutral'),
    moodConfidence: (json['moodConfidence'] as num?)?.toDouble() ?? 0,
    harmConfidence: (json['harmConfidence'] as num?)?.toDouble() ?? 0,
    harmReason: (json['harmReason'] as String?) ?? '',
    softenedText: json['softenedText'] as String?,
    isOwn: (json['isOwn'] as bool?) ?? false,
    isModerator: (json['isModerator'] as bool?) ?? false,
  );
}

@immutable
final class DiscoveryPreference {
  const DiscoveryPreference({
    this.categories = const <String>[],
    this.languages = const <String>['en'],
    this.excludedChannels = const <String>[],
    this.technicalWeight = 0.7,
    this.preferLowResource = false,
  });

  final List<String> categories;
  final List<String> languages;
  final List<String> excludedChannels;
  final double technicalWeight;
  final bool preferLowResource;

  Map<String, Object?> toJson() => <String, Object?>{
    'categories': categories,
    'languages': languages,
    'excludedChannels': excludedChannels,
    'technicalWeight': technicalWeight,
    'preferLowResource': preferLowResource,
  };

  static DiscoveryPreference fromJson(Map<String, Object?> json) =>
      DiscoveryPreference(
        categories: List<String>.from(
          (json['categories'] as List<Object?>?) ?? const <Object?>[],
        ),
        languages: List<String>.from(
          (json['languages'] as List<Object?>?) ?? const <Object?>['en'],
        ),
        excludedChannels: List<String>.from(
          (json['excludedChannels'] as List<Object?>?) ?? const <Object?>[],
        ),
        technicalWeight: (json['technicalWeight'] as num?)?.toDouble() ?? 0.7,
        preferLowResource: (json['preferLowResource'] as bool?) ?? false,
      );

  DiscoveryPreference copyWith({
    List<String>? categories,
    List<String>? languages,
    List<String>? excludedChannels,
    double? technicalWeight,
    bool? preferLowResource,
  }) => DiscoveryPreference(
    categories: categories ?? this.categories,
    languages: languages ?? this.languages,
    excludedChannels: excludedChannels ?? this.excludedChannels,
    technicalWeight: technicalWeight ?? this.technicalWeight,
    preferLowResource: preferLowResource ?? this.preferLowResource,
  );
}

@immutable
final class AiFeatureSettings {
  const AiFeatureSettings({
    this.enabled = false,
    this.moodColoring = false,
    this.protectiveMode = ProtectiveMode.raw,
    this.jokeMode = false,
    this.technicalCompanion = false,
    this.calmingComposer = false,
    this.speechContext = false,
    this.closedCaptions = false,
    this.retainTranscripts = false,
    this.memoryEnabled = false,
    this.batchMinutes = 7,
    this.safetySensitivity = 0.7,
    this.backend = AiBackend.gpuFirst,
    this.modelDirectory = '',
    this.autoLoadModel = false,
  });

  final bool enabled;
  final bool moodColoring;
  final ProtectiveMode protectiveMode;
  final bool jokeMode;
  final bool technicalCompanion;
  final bool calmingComposer;
  final bool speechContext;
  final bool closedCaptions;
  final bool retainTranscripts;
  final bool memoryEnabled;
  final int batchMinutes;
  final double safetySensitivity;
  final AiBackend backend;
  final String modelDirectory;
  final bool autoLoadModel;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'moodColoring': moodColoring,
    'protectiveMode': protectiveMode.name,
    'jokeMode': jokeMode,
    'technicalCompanion': technicalCompanion,
    'calmingComposer': calmingComposer,
    'speechContext': speechContext,
    'closedCaptions': closedCaptions,
    'retainTranscripts': retainTranscripts,
    'memoryEnabled': memoryEnabled,
    'batchMinutes': batchMinutes,
    'safetySensitivity': safetySensitivity,
    'backend': backend.name,
    'modelDirectory': modelDirectory,
    'autoLoadModel': autoLoadModel,
  };

  static AiFeatureSettings fromJson(Map<String, Object?> json) =>
      AiFeatureSettings(
        enabled: (json['enabled'] as bool?) ?? false,
        moodColoring: (json['moodColoring'] as bool?) ?? false,
        protectiveMode: ProtectiveMode.values.byName(
          (json['protectiveMode'] as String?) ?? 'raw',
        ),
        jokeMode: (json['jokeMode'] as bool?) ?? false,
        technicalCompanion: (json['technicalCompanion'] as bool?) ?? false,
        calmingComposer: (json['calmingComposer'] as bool?) ?? false,
        speechContext: (json['speechContext'] as bool?) ?? false,
        closedCaptions: (json['closedCaptions'] as bool?) ?? false,
        retainTranscripts: (json['retainTranscripts'] as bool?) ?? false,
        memoryEnabled: (json['memoryEnabled'] as bool?) ?? false,
        batchMinutes: (json['batchMinutes'] as num?)?.toInt() ?? 7,
        safetySensitivity:
            (json['safetySensitivity'] as num?)?.toDouble() ?? 0.7,
        backend: AiBackend.values.byName(
          (json['backend'] as String?) ?? 'gpuFirst',
        ),
        modelDirectory: (json['modelDirectory'] as String?) ?? '',
        autoLoadModel: (json['autoLoadModel'] as bool?) ?? false,
      );

  AiFeatureSettings copyWith({
    bool? enabled,
    bool? moodColoring,
    ProtectiveMode? protectiveMode,
    bool? jokeMode,
    bool? technicalCompanion,
    bool? calmingComposer,
    bool? speechContext,
    bool? closedCaptions,
    bool? retainTranscripts,
    bool? memoryEnabled,
    int? batchMinutes,
    double? safetySensitivity,
    AiBackend? backend,
    String? modelDirectory,
    bool? autoLoadModel,
  }) => AiFeatureSettings(
    enabled: enabled ?? this.enabled,
    moodColoring: moodColoring ?? this.moodColoring,
    protectiveMode: protectiveMode ?? this.protectiveMode,
    jokeMode: jokeMode ?? this.jokeMode,
    technicalCompanion: technicalCompanion ?? this.technicalCompanion,
    calmingComposer: calmingComposer ?? this.calmingComposer,
    speechContext: speechContext ?? this.speechContext,
    closedCaptions: closedCaptions ?? this.closedCaptions,
    retainTranscripts: retainTranscripts ?? this.retainTranscripts,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    batchMinutes: batchMinutes ?? this.batchMinutes,
    safetySensitivity: safetySensitivity ?? this.safetySensitivity,
    backend: backend ?? this.backend,
    modelDirectory: modelDirectory ?? this.modelDirectory,
    autoLoadModel: autoLoadModel ?? this.autoLoadModel,
  );
}

@immutable
final class AppPreferences {
  const AppPreferences({
    this.theme = ThemeProfile.auroraViolet,
    this.drawerOpen = false,
    this.showStreamTitles = true,
    this.reduceMotion = false,
    this.compactDensity = false,
    this.autoLockMinutes = 20,
    this.preferredQuality = '720p',
    this.lowLatency = true,
    this.videoAcceleration = VideoAcceleration.automatic,
    this.discovery = const DiscoveryPreference(),
    this.ai = const AiFeatureSettings(),
  });

  final ThemeProfile theme;
  final bool drawerOpen;
  final bool showStreamTitles;
  final bool reduceMotion;
  final bool compactDensity;
  final int autoLockMinutes;
  final String preferredQuality;
  final bool lowLatency;
  final VideoAcceleration videoAcceleration;
  final DiscoveryPreference discovery;
  final AiFeatureSettings ai;

  Map<String, Object?> toJson() => <String, Object?>{
    'theme': theme.name,
    'drawerOpen': drawerOpen,
    'showStreamTitles': showStreamTitles,
    'reduceMotion': reduceMotion,
    'compactDensity': compactDensity,
    'autoLockMinutes': autoLockMinutes,
    'preferredQuality': preferredQuality,
    'lowLatency': lowLatency,
    'videoAcceleration': videoAcceleration.name,
    'discovery': discovery.toJson(),
    'ai': ai.toJson(),
  };

  static AppPreferences fromJson(Map<String, Object?> json) => AppPreferences(
    theme: ThemeProfile.values.byName(
      (json['theme'] as String?) ?? 'auroraViolet',
    ),
    drawerOpen: (json['drawerOpen'] as bool?) ?? false,
    showStreamTitles: (json['showStreamTitles'] as bool?) ?? true,
    reduceMotion: (json['reduceMotion'] as bool?) ?? false,
    compactDensity: (json['compactDensity'] as bool?) ?? false,
    autoLockMinutes: (json['autoLockMinutes'] as num?)?.toInt() ?? 20,
    preferredQuality: (json['preferredQuality'] as String?) ?? '720p',
    lowLatency: (json['lowLatency'] as bool?) ?? true,
    videoAcceleration: VideoAcceleration.values.firstWhere(
      (VideoAcceleration value) => value.name == json['videoAcceleration'],
      orElse: () => VideoAcceleration.automatic,
    ),
    discovery: DiscoveryPreference.fromJson(
      Map<String, Object?>.from(
        (json['discovery'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
    ),
    ai: AiFeatureSettings.fromJson(
      Map<String, Object?>.from(
        (json['ai'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
      ),
    ),
  );

  AppPreferences copyWith({
    ThemeProfile? theme,
    bool? drawerOpen,
    bool? showStreamTitles,
    bool? reduceMotion,
    bool? compactDensity,
    int? autoLockMinutes,
    String? preferredQuality,
    bool? lowLatency,
    VideoAcceleration? videoAcceleration,
    DiscoveryPreference? discovery,
    AiFeatureSettings? ai,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    drawerOpen: drawerOpen ?? this.drawerOpen,
    showStreamTitles: showStreamTitles ?? this.showStreamTitles,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    compactDensity: compactDensity ?? this.compactDensity,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    lowLatency: lowLatency ?? this.lowLatency,
    videoAcceleration: videoAcceleration ?? this.videoAcceleration,
    discovery: discovery ?? this.discovery,
    ai: ai ?? this.ai,
  );
}

Color moodColor(MoodLabel mood, ColorScheme scheme) => switch (mood) {
  MoodLabel.supportive => const Color(0xFF5CE1B9),
  MoodLabel.joyful => const Color(0xFFFFD166),
  MoodLabel.curious => const Color(0xFF74C7EC),
  MoodLabel.technical => const Color(0xFF8BE9FD),
  MoodLabel.neutral => scheme.onSurfaceVariant,
  MoodLabel.tense => const Color(0xFFFFA657),
  MoodLabel.sarcastic => const Color(0xFFCBA6F7),
  MoodLabel.sad => const Color(0xFF89B4FA),
  MoodLabel.hostile => const Color(0xFFFF6B8A),
  MoodLabel.uncertain => const Color(0xFFA6ADC8),
};

String encodeJsonObject(Map<String, Object?> value) => jsonEncode(value);
Map<String, Object?> decodeJsonObject(String value) =>
    Map<String, Object?>.from(jsonDecode(value) as Map<Object?, Object?>);
