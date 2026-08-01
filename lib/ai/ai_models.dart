import '../core/models.dart';

final class MessageAssessment {
  const MessageAssessment({
    required this.messageId,
    required this.mood,
    required this.moodConfidence,
    required this.harmConfidence,
    required this.harmReason,
    required this.softenedText,
  });

  final String messageId;
  final MoodLabel mood;
  final double moodConfidence;
  final double harmConfidence;
  final String harmReason;
  final String? softenedText;

  factory MessageAssessment.fromJson(Map<String, Object?> json) =>
      MessageAssessment(
        messageId: (json['message_id'] as String?) ?? '',
        mood:
            MoodLabel.values
                .where((MoodLabel item) => item.name == json['mood'])
                .firstOrNull ??
            MoodLabel.uncertain,
        moodConfidence: ((json['mood_confidence'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
        harmConfidence: ((json['harm_confidence'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
        harmReason: (json['harm_reason'] as String?) ?? '',
        softenedText: json['softened_text'] as String?,
      );
}

final class AiBatchReport {
  const AiBatchReport({
    required this.assessments,
    required this.summary,
    required this.patternNotice,
    required this.calmOptions,
    required this.joke,
    required this.technicalNote,
  });

  final List<MessageAssessment> assessments;
  final String summary;
  final String patternNotice;
  final List<String> calmOptions;
  final String joke;
  final String technicalNote;

  static const empty = AiBatchReport(
    assessments: <MessageAssessment>[],
    summary: '',
    patternNotice: '',
    calmOptions: <String>[],
    joke: '',
    technicalNote: '',
  );
}

final class CompanionCard {
  const CompanionCard({
    required this.id,
    required this.role,
    required this.title,
    required this.body,
    required this.createdAt,
    this.confidence,
  });

  final String id;
  final AgentRole role;
  final String title;
  final String body;
  final DateTime createdAt;
  final double? confidence;
}

final class TranscriptSegment {
  const TranscriptSegment({
    required this.channel,
    required this.startedAt,
    required this.endedAt,
    required this.text,
  });
  final String channel;
  final DateTime startedAt;
  final DateTime endedAt;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'channel': channel,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'text': text,
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
