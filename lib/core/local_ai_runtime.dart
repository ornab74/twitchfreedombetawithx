import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

Future<void>? _speechInitialization;

/// Registers only the speech backend. Gemma's LiteRT-LM engine is opened
/// directly by GemmaRuntime when the user explicitly requests the LLM, so a
/// caption-only session never loads or registers the multi-gigabyte LLM path.
Future<void> ensureSpeechRuntimeInitialized() {
  return _speechInitialization ??= FlutterGemma.initialize(
    sttBackends: const [LiteRtSttBackend()],
    maxDownloadRetries: 3,
  );
}
