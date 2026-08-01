import 'dart:convert';

import '../core/models.dart';
import '../security/vault.dart';
import 'ai_models.dart';

final class ChannelMemory {
  const ChannelMemory({
    required this.channel,
    required this.summary,
    required this.topics,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String channel;
  final String summary;
  final List<String> topics;
  final DateTime updatedAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'channel': channel,
    'summary': summary,
    'topics': topics,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  static ChannelMemory fromJson(Map<String, Object?> json) => ChannelMemory(
    channel: json['channel']! as String,
    summary: (json['summary'] as String?) ?? '',
    topics: List<String>.from(
      (json['topics'] as List<Object?>?) ?? const <Object?>[],
    ),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    expiresAt: DateTime.parse(json['expiresAt']! as String),
  );
}

/// Encrypted, channel-isolated memory. It stores compact derived summaries,
/// never raw audio, and only stores raw chat when the user separately enables it.
final class AiMemoryStore {
  AiMemoryStore(this._vault);

  final VaultRepository _vault;

  Future<ChannelMemory?> getChannelMemory(String channel) async {
    final json = await _vault.getJson(
      'ai_channel_memory',
      channel.toLowerCase(),
    );
    if (json == null) return null;
    final memory = ChannelMemory.fromJson(json);
    if (memory.expiresAt.isBefore(DateTime.now())) {
      await deleteChannel(channel);
      return null;
    }
    return memory;
  }

  Future<void> saveChannelMemory(ChannelMemory memory) => _vault.putJson(
    'ai_channel_memory',
    memory.channel.toLowerCase(),
    memory.toJson(),
  );

  Future<void> saveTranscript(
    TranscriptSegment segment, {
    Duration ttl = const Duration(hours: 12),
  }) async {
    final bucket =
        '${segment.channel}:${segment.startedAt.toUtc().toIso8601String()}';
    await _vault.putJson('ai_transcript_segment', bucket, <String, Object?>{
      ...segment.toJson(),
      'expiresAt': DateTime.now().add(ttl).toUtc().toIso8601String(),
    });
  }

  Future<void> saveRecentMessages(
    String channel,
    List<ChatMessage> messages,
  ) async {
    await _vault
        .putJson('ai_recent_chat', channel.toLowerCase(), <String, Object?>{
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'messages': messages
              .take(120)
              .map((ChatMessage item) => item.toJson())
              .toList(growable: false),
        });
  }

  Future<void> deleteChannel(String channel) async {
    await _vault.delete('ai_channel_memory', channel.toLowerCase());
    await _vault.delete('ai_recent_chat', channel.toLowerCase());
  }

  Future<String> contextPacket(String channel) async {
    final memory = await getChannelMemory(channel);
    if (memory == null) return '{}';
    return jsonEncode(memory.toJson());
  }
}
