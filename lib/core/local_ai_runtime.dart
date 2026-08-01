import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

Future<void>? _initialization;

/// Initializes native AI backends only after the encrypted workspace unlocks
/// and the user explicitly requests an AI or speech operation.
Future<void> ensureLocalAiRuntimeInitialized() {
  return _initialization ??= FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
    sttBackends: const [LiteRtSttBackend()],
    maxDownloadRetries: 3,
  );
}
