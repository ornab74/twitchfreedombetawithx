import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/pulse_scheduler.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import 'ai_models.dart';
import 'gemma_runtime.dart';
import 'memory_store.dart';
import 'prompts.dart';

final class AgentOrchestrator {
  AgentOrchestrator({
    required GemmaRuntime runtime,
    required AiMemoryStore memory,
    required SecureLog log,
    required PulseScheduler scheduler,
  }) : _runtime = runtime,
       _memory = memory,
       _log = log,
       _scheduler = scheduler;

  final GemmaRuntime _runtime;
  final AiMemoryStore _memory;
  final SecureLog _log;
  final PulseScheduler _scheduler;
  final Uuid _uuid = const Uuid();
  final StreamController<CompanionCard> _cards =
      StreamController<CompanionCard>.broadcast();
  final StreamController<AiBatchReport> _reports =
      StreamController<AiBatchReport>.broadcast();
  PulseRecurringHandle? _batchRecurring;
  final Queue<DateTime> _messageArrivals = Queue<DateTime>();
  String _channel = '';
  String _speechContext = '';
  bool _speechContextDirty = false;
  AiFeatureSettings _settings = const AiFeatureSettings();
  final List<ChatMessage> _pending = <ChatMessage>[];

  Stream<CompanionCard> get cards => _cards.stream;
  Stream<AiBatchReport> get reports => _reports.stream;

  void configure({
    required String channel,
    required AiFeatureSettings settings,
    required List<ChatMessage> initialMessages,
  }) {
    _batchRecurring?.cancel();
    _scheduler.cancelScope('agent-batch');
    _scheduler.reopenScope('agent-batch');
    _runtime.cancel();
    _channel = channel;
    _settings = settings;
    _speechContext = '';
    _speechContextDirty = false;
    _messageArrivals.clear();
    _pending
      ..clear()
      ..addAll(
        initialMessages.length <= 120
            ? initialMessages
            : initialMessages.sublist(initialMessages.length - 120),
      );
    if (settings.enabled && channel.isNotEmpty) {
      _batchRecurring = _scheduler.scheduleAdaptiveRecurring(
        key: 'agent-batch-trigger:$channel',
        scope: 'agent-batch',
        lane: PulseLane.ai,
        affinity: 'gemma:$channel',
        priority: 48,
        cost: 34,
        requiresVault: true,
        requiresModel: true,
        cadence: (_) => _adaptiveCadence(),
        enabledWhen: (_) => _pending.isNotEmpty || _speechContextDirty,
        action: (_) async {
          await _runBatchCore();
        },
      );
    }
  }

  void addMessage(ChatMessage message) {
    if (!_settings.enabled || message.channel != _channel) return;
    _pending.add(message);
    final now = DateTime.now();
    _messageArrivals.addLast(now);
    _trimArrivalWindow(now);
    if (_pending.length > 180) _pending.removeRange(0, _pending.length - 180);
  }

  void addSpeechContext(String text) {
    if (!_settings.enabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;
    final merged = mergeTranscriptChunks(_speechContext, clean);
    if (merged == _speechContext) return;
    _speechContext = merged;
    _speechContextDirty = true;
  }

  Future<AppResult<AiBatchReport>> runBatch({bool userInitiated = false}) {
    if (!_settings.enabled) {
      return Future<AppResult<AiBatchReport>>.value(
        const AppSuccess<AiBatchReport>(AiBatchReport.empty),
      );
    }
    if (!_runtime.isReady) {
      return Future<AppResult<AiBatchReport>>.value(
        const AppError<AiBatchReport>(
          AppFailure('model_not_ready', 'Load the local model first.'),
        ),
      );
    }
    return _scheduler.schedule<AppResult<AiBatchReport>>(
      PulseTaskSpec<AppResult<AiBatchReport>>(
        key: 'agent-batch-exec:${_channel.isEmpty ? 'none' : _channel}',
        scope: 'agent-batch',
        lane: PulseLane.ai,
        affinity: 'gemma:$_channel',
        priority: userInitiated ? 88 : 48,
        cost: 34,
        deadline: DateTime.now().add(
          userInitiated
              ? const Duration(seconds: 20)
              : const Duration(minutes: 2),
        ),
        requiresVault: true,
        requiresModel: true,
        retryPolicy: const PulseRetryPolicy(maxAttempts: 2),
        action: (_) => _runBatchCore(),
      ),
    );
  }

  Future<AppResult<AiBatchReport>> _runBatchCore() async {
    if (!_settings.enabled)
      return const AppSuccess<AiBatchReport>(AiBatchReport.empty);
    if (!_runtime.isReady)
      return const AppError<AiBatchReport>(
        AppFailure('model_not_ready', 'Load the local model first.'),
      );
    if (_pending.isEmpty && !_speechContextDirty)
      return const AppSuccess<AiBatchReport>(AiBatchReport.empty);

    final batch = List<ChatMessage>.from(_pending.take(120));
    if (batch.isNotEmpty) _pending.removeRange(0, batch.length);
    final speechContext = _speechContextDirty ? _speechContext : '';
    _speechContextDirty = false;
    final prompt = AgentPrompts.batchAnalysis(
      messages: batch,
      speechContext: speechContext,
      sensitivity: _settings.safetySensitivity,
      enableJokes: _settings.jokeMode,
      enableTechnical: _settings.technicalCompanion,
      enableCalming: _settings.calmingComposer,
    );
    final response = await _runtime.generate(
      role: AgentRole.safety,
      systemInstruction: AgentPrompts.invariant,
      prompt: prompt,
      maxOutputTokens: 1800,
      temperature: 0.15,
    );
    return response.fold(
      success: (String text) {
        try {
          final decoded = _decodeObject(text);
          final assessments =
              ((decoded['assessments'] as List<Object?>?) ?? const <Object?>[])
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (Map<Object?, Object?> item) => MessageAssessment.fromJson(
                      Map<String, Object?>.from(item),
                    ),
                  )
                  .where((MessageAssessment item) => item.messageId.isNotEmpty)
                  .toList(growable: false);
          final report = AiBatchReport(
            assessments: assessments,
            summary: _bounded(decoded['summary'], 700),
            patternNotice: _bounded(decoded['pattern_notice'], 400),
            calmOptions:
                ((decoded['calm_options'] as List<Object?>?) ??
                        const <Object?>[])
                    .map((Object? item) => _bounded(item, 180))
                    .where((String item) => item.isNotEmpty)
                    .take(6)
                    .toList(growable: false),
            joke: _bounded(decoded['joke'], 400),
            technicalNote: _bounded(decoded['technical_note'], 900),
          );
          if (!_reports.isClosed) _reports.add(report);
          _emitCards(report);
          if (_settings.memoryEnabled &&
              _channel.isNotEmpty &&
              report.summary.isNotEmpty) {
            unawaited(
              _memory.saveChannelMemory(
                ChannelMemory(
                  channel: _channel,
                  summary: report.summary,
                  topics: _extractTopics(report.technicalNote),
                  updatedAt: DateTime.now(),
                  expiresAt: DateTime.now().add(const Duration(days: 14)),
                ),
              ),
            );
          }
          return AppSuccess<AiBatchReport>(report);
        } catch (cause) {
          _requeue(batch);
          if (speechContext.isNotEmpty) _speechContextDirty = true;
          _log.warning('AI batch JSON was rejected: $cause');
          return AppError<AiBatchReport>(
            AppFailure(
              'invalid_ai_json',
              'The local model returned an invalid structured report.',
              cause: cause,
            ),
          );
        }
      },
      failure: (AppFailure failure) {
        _requeue(batch);
        if (speechContext.isNotEmpty) _speechContextDirty = true;
        return AppError<AiBatchReport>(failure);
      },
    );
  }

  Duration _adaptiveCadence() {
    final now = DateTime.now();
    _trimArrivalWindow(now);
    final perMinute = _messageArrivals.length;
    final configured = _settings.batchMinutes.clamp(5, 10).toInt();
    final minutes = switch (perMinute) {
      >= 45 => 5,
      >= 20 => 6,
      >= 8 => 7,
      >= 3 => 8,
      _ => 10,
    };
    return Duration(
      minutes: minutes.clamp(5, configured == 5 ? 5 : 10).toInt(),
    );
  }

  void _trimArrivalWindow(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    while (_messageArrivals.isNotEmpty &&
        _messageArrivals.first.isBefore(cutoff)) {
      _messageArrivals.removeFirst();
    }
  }

  Future<AppResult<Map<String, String>>> rerankDiscovery({
    required DiscoveryPreference preference,
    required List<Map<String, Object?>> candidates,
  }) async {
    if (!_settings.enabled || !_runtime.isReady || candidates.length < 2) {
      return const AppSuccess<Map<String, String>>(<String, String>{});
    }
    final response = await _runtime.generate(
      role: AgentRole.discovery,
      systemInstruction: AgentPrompts.invariant,
      prompt: AgentPrompts.discoveryRerank(
        preference: preference,
        candidates: candidates.take(40).toList(growable: false),
      ),
      maxOutputTokens: 900,
      temperature: 0.1,
    );
    return response.fold(
      success: (String text) {
        try {
          final decoded = _decodeObject(text);
          final ordered =
              ((decoded['ordered_ids'] as List<Object?>?) ?? const <Object?>[])
                  .map((Object? value) => value?.toString() ?? '')
                  .where((String value) => value.isNotEmpty)
                  .toList(growable: false);
          final rawReasons = decoded['reasons'];
          final reasons = rawReasons is Map<Object?, Object?>
              ? rawReasons.map(
                  (Object? key, Object? value) => MapEntry<String, String>(
                    key?.toString() ?? '',
                    _bounded(value, 180),
                  ),
                )
              : <String, String>{};
          return AppSuccess<Map<String, String>>(<String, String>{
            for (var index = 0; index < ordered.length; index++)
              ordered[index]:
                  '${index.toString().padLeft(3, '0')}|${reasons[ordered[index]] ?? ''}',
          });
        } catch (cause) {
          return AppError<Map<String, String>>(
            AppFailure(
              'invalid_discovery_json',
              'The local discovery agent returned invalid structured data.',
              cause: cause,
            ),
          );
        }
      },
      failure: (AppFailure failure) => AppError<Map<String, String>>(failure),
    );
  }

  Future<AppResult<String>> answerTechnicalQuestion(
    String question,
    List<ChatMessage> recentChat,
  ) async {
    final result = await _runtime.generate(
      role: AgentRole.technical,
      systemInstruction: AgentPrompts.invariant,
      prompt: AgentPrompts.technicalQuestion(
        question: question,
        transcript: _speechContext,
        recentChat: recentChat,
      ),
      maxOutputTokens: 900,
      temperature: 0.25,
    );
    if (result case AppSuccess<String>(:final value)) {
      _emit(AgentRole.technical, 'Technical companion reply', value);
    }
    return result;
  }

  void _requeue(List<ChatMessage> batch) {
    if (batch.isEmpty) return;
    _pending.insertAll(0, batch);
    if (_pending.length > 180) {
      _pending.removeRange(180, _pending.length);
    }
  }

  void _emitCards(AiBatchReport report) {
    if (report.patternNotice.isNotEmpty)
      _emit(AgentRole.safety, 'Protective review', report.patternNotice);
    if (report.joke.isNotEmpty) _emit(AgentRole.joke, 'Joke mode', report.joke);
    if (report.technicalNote.isNotEmpty)
      _emit(AgentRole.technical, 'Technical companion', report.technicalNote);
    if (report.calmOptions.isNotEmpty)
      _emit(
        AgentRole.calming,
        'Calm options',
        report.calmOptions.map((String item) => '• $item').join('\n'),
      );
    if (report.summary.isNotEmpty)
      _emit(AgentRole.summary, 'Batch summary', report.summary);
  }

  void _emit(AgentRole role, String title, String body) {
    if (_cards.isClosed) return;
    _cards.add(
      CompanionCard(
        id: _uuid.v4(),
        role: role,
        title: title,
        body: body,
        createdAt: DateTime.now(),
      ),
    );
  }

  Map<String, Object?> _decodeObject(String text) {
    var clean = text.trim();
    if (clean.startsWith('```')) {
      clean = clean
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start < 0 || end <= start)
      throw const FormatException('No JSON object.');
    final decoded = jsonDecode(clean.substring(start, end + 1));
    if (decoded is! Map<Object?, Object?>)
      throw const FormatException('Expected JSON object.');
    return Map<String, Object?>.from(decoded);
  }

  String _bounded(Object? value, int limit) {
    final text = (value as String? ?? '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();
    return text.length <= limit ? text : '${text.substring(0, limit)}…';
  }

  List<String> _extractTopics(String technical) {
    return technical
        .split(RegExp(r'[,.;\n]'))
        .map((String item) => item.trim())
        .where((String item) => item.length >= 4 && item.length <= 80)
        .take(12)
        .toList(growable: false);
  }

  Future<void> close() async {
    _batchRecurring?.cancel();
    _scheduler.cancelScope('agent-batch');
    await _cards.close();
    await _reports.close();
  }
}

/// Adds a new fixed-window transcript without repeating words shared by two
/// adjacent capture windows. The rolling context is deliberately bounded so
/// it cannot crowd the LLM's response budget.
String mergeTranscriptChunks(
  String existing,
  String incoming, {
  int limit = 6000,
}) {
  final left = existing.trim();
  final right = incoming.trim();
  if (right.isEmpty) return left;
  if (left.isEmpty) return _tail(right, limit);

  final leftWords = left.split(RegExp(r'\s+'));
  final rightWords = right.split(RegExp(r'\s+'));
  final maximumOverlap = <int>[
    leftWords.length,
    rightWords.length,
    24,
  ].reduce((int a, int b) => a < b ? a : b);
  var overlap = 0;
  for (var count = maximumOverlap; count >= 2; count--) {
    final leftTail = leftWords
        .sublist(leftWords.length - count)
        .join(' ')
        .toLowerCase();
    final rightHead = rightWords.sublist(0, count).join(' ').toLowerCase();
    if (leftTail == rightHead) {
      overlap = count;
      break;
    }
  }
  final addition = rightWords.skip(overlap).join(' ');
  return _tail(addition.isEmpty ? left : '$left $addition', limit);
}

String _tail(String value, int limit) =>
    value.length <= limit ? value : value.substring(value.length - limit);
