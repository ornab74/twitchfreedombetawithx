import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/app_config.dart';
import '../core/local_ai_runtime.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import '../playback/playback_controller.dart';
import '../security/vault.dart';
import 'ai_models.dart';
import 'memory_store.dart';

final class SpeechContextState {
  const SpeechContextState({
    required this.installed,
    required this.active,
    required this.busy,
    required this.modelProgress,
    required this.tokenizerProgress,
    this.message = '',
  });

  final bool installed;
  final bool active;
  final bool busy;
  final double modelProgress;
  final double tokenizerProgress;
  final String message;

  double get progress => (modelProgress + tokenizerProgress) / 2;
}

const int moonshinePcmBytesPerSample = 2;
const int moonshineWindowBytes = 16000 * 5 * moonshinePcmBytesPerSample;

/// Produces the exact fixed input shape used by Moonshine Tiny: five seconds
/// of 16 kHz mono signed 16-bit little-endian PCM. Short final chunks receive
/// zero padding and oversized captures are trimmed without splitting a sample.
Uint8List prepareMoonshinePcmWindow(Uint8List pcm) {
  final alignedLength = pcm.lengthInBytes - (pcm.lengthInBytes % 2);
  final copyLength = alignedLength.clamp(0, moonshineWindowBytes);
  final window = Uint8List(moonshineWindowBytes);
  window.setRange(0, copyLength, pcm);
  return window;
}

/// Privacy-preserving speech context pipeline. Moonshine is installed from
/// revision-pinned public artifacts. Playback audio is reduced to a bounded
/// five-second 16 kHz mono PCM window, transcribed locally, overwritten on a
/// best-effort basis, and deleted in a finally block.
final class SpeechContextService {
  SpeechContextService({
    required UnifiedPlaybackController playback,
    required AiMemoryStore memory,
    required VaultRepository vault,
    required SecureLog log,
  }) : _playback = playback,
       _memory = memory,
       _vault = vault,
       _log = log;

  final UnifiedPlaybackController _playback;
  final AiMemoryStore _memory;
  final VaultRepository _vault;
  final SecureLog _log;
  final StreamController<SpeechContextState> _states =
      StreamController<SpeechContextState>.broadcast();

  SpeechRecognizer? _recognizer;
  SpeechContextState _current = const SpeechContextState(
    installed: false,
    active: false,
    busy: false,
    modelProgress: 0,
    tokenizerProgress: 0,
  );

  Stream<SpeechContextState> get states => _states.stream;
  SpeechContextState get current => _current;
  bool get busy => _current.busy;
  bool get active => _recognizer != null;

  Future<void> refreshInstallationState() async {
    final attestation = _vault.isUnlocked
        ? await _vault.getJson('speech_attestation', AppConfig.moonshineProfile)
        : null;
    final installed =
        attestation?['modelRevision'] == AppConfig.moonshineModelRevision &&
        attestation?['tokenizerRevision'] ==
            AppConfig.moonshineTokenizerRevision;
    _emit(
      SpeechContextState(
        installed: installed,
        active: active,
        busy: false,
        modelProgress: installed ? 1 : 0,
        tokenizerProgress: installed ? 1 : 0,
        message: installed
            ? 'Moonshine speech pack registered.'
            : 'Moonshine speech pack is not installed.',
      ),
    );
  }

  Future<AppResult<void>> installMoonshine({
    void Function(double progress)? onProgress,
  }) async {
    if (!_vault.isUnlocked) {
      return const AppError<void>(
        AppFailure(
          'vault_locked',
          'Unlock the vault before installing speech models.',
        ),
      );
    }
    var modelProgress = 0.0;
    var tokenizerProgress = 0.0;
    void update(String message) {
      final state = SpeechContextState(
        installed: false,
        active: false,
        busy: true,
        modelProgress: modelProgress,
        tokenizerProgress: tokenizerProgress,
        message: message,
      );
      _emit(state);
      onProgress?.call(state.progress);
    }

    try {
      await ensureLocalAiRuntimeInitialized();
      update('Installing revision-pinned Moonshine speech pack…');
      await FlutterGemma.installStt()
          .modelFromNetwork(AppConfig.moonshineModelUri.toString())
          .tokenizerFromNetwork(AppConfig.moonshineTokenizerUri.toString())
          .ofType(SttModelType.moonshine)
          .withModelProgress((int value) {
            modelProgress = (value / 100).clamp(0.0, 1.0).toDouble();
            update('Installing Moonshine model…');
          })
          .withTokenizerProgress((int value) {
            tokenizerProgress = (value / 100).clamp(0.0, 1.0).toDouble();
            update('Installing Moonshine tokenizer…');
          })
          .install();

      await _vault.putJson('speech_attestation', AppConfig.moonshineProfile, <
        String,
        Object?
      >{
        'profile': AppConfig.moonshineProfile,
        'modelRevision': AppConfig.moonshineModelRevision,
        'tokenizerRevision': AppConfig.moonshineTokenizerRevision,
        'modelSource': AppConfig.moonshineModelUri.toString(),
        'tokenizerSource': AppConfig.moonshineTokenizerUri.toString(),
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'note':
            'Revision-pinned package-managed installation; no digest claim is made.',
      });
      final attached = await attachActiveMoonshine();
      if (attached is AppError<void>) return attached;
      _emit(
        const SpeechContextState(
          installed: true,
          active: true,
          busy: false,
          modelProgress: 1,
          tokenizerProgress: 1,
          message: 'Moonshine is ready for local five-second speech windows.',
        ),
      );
      return const AppSuccess<void>(null);
    } catch (cause) {
      _log.warning('Moonshine installation failed: $cause');
      _emit(
        SpeechContextState(
          installed: false,
          active: false,
          busy: false,
          modelProgress: modelProgress,
          tokenizerProgress: tokenizerProgress,
          message: 'Moonshine installation failed.',
        ),
      );
      return AppError<void>(
        AppFailure(
          'stt_install_failed',
          'The local Moonshine speech pack could not be installed.',
          cause: cause,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<void>> attachActiveMoonshine() async {
    try {
      await ensureLocalAiRuntimeInitialized();
      await _recognizer?.close();
      _recognizer = await FlutterGemma.getActiveStt();
      _emit(
        SpeechContextState(
          installed: true,
          active: true,
          busy: false,
          modelProgress: 1,
          tokenizerProgress: 1,
          message: 'Moonshine active.',
        ),
      );
      return const AppSuccess<void>(null);
    } catch (cause) {
      return AppError<void>(
        AppFailure(
          'stt_not_installed',
          'Install and activate the Moonshine speech pack before enabling streamer speech context.',
          cause: cause,
        ),
      );
    }
  }

  Future<AppResult<TranscriptSegment>> capture({
    required String channel,
    bool retainEncryptedText = false,
  }) async {
    if (_current.busy) {
      return const AppError<TranscriptSegment>(
        AppFailure('stt_busy', 'A speech window is already being processed.'),
      );
    }
    final recognizer = _recognizer;
    if (recognizer == null) {
      return const AppError<TranscriptSegment>(
        AppFailure(
          'stt_inactive',
          'Activate the local speech recognizer first.',
        ),
      );
    }

    _emit(
      SpeechContextState(
        installed: true,
        active: true,
        busy: true,
        modelProgress: 1,
        tokenizerProgress: 1,
        message: 'Capturing an ephemeral five-second speech window…',
      ),
    );
    File? pcm;
    final start = DateTime.now();
    try {
      final capture = await _playback.captureSpeechWindow(
        duration: AppConfig.moonshineWindow,
      );
      pcm = capture.fold<File?>(
        success: (File value) => value,
        failure: (_) => null,
      );
      if (pcm == null) {
        return const AppError<TranscriptSegment>(
          AppFailure(
            'speech_capture_failed',
            'Could not capture a private speech window.',
          ),
        );
      }
      final rawBytes = Uint8List.fromList(await pcm.readAsBytes());
      if (rawBytes.length > AppConfig.moonshineMaximumPcmBytes) {
        return const AppError<TranscriptSegment>(
          AppFailure(
            'speech_window_too_large',
            'The speech window exceeded its memory budget.',
          ),
        );
      }
      if (rawBytes.length < 16000) {
        return const AppError<TranscriptSegment>(
          AppFailure(
            'speech_window_too_short',
            'The captured audio chunk was too short to transcribe reliably.',
            retryable: true,
          ),
        );
      }
      final bytes = prepareMoonshinePcmWindow(rawBytes);
      final text = (await recognizer.transcribe(bytes)).trim();
      if (text.isEmpty) {
        return const AppError<TranscriptSegment>(
          AppFailure(
            'speech_empty',
            'No speech was recognized in this window.',
          ),
        );
      }
      final segment = TranscriptSegment(
        channel: channel,
        startedAt: start,
        endedAt: DateTime.now(),
        text: text,
      );
      if (retainEncryptedText) await _memory.saveTranscript(segment);
      return AppSuccess<TranscriptSegment>(segment);
    } catch (cause) {
      _log.warning('Local speech transcription failed: $cause');
      return AppError<TranscriptSegment>(
        AppFailure(
          'speech_transcription_failed',
          'Local speech transcription failed.',
          cause: cause,
        ),
      );
    } finally {
      await _destroyEphemeralFile(pcm);
      _emit(
        const SpeechContextState(
          installed: true,
          active: true,
          busy: false,
          modelProgress: 1,
          tokenizerProgress: 1,
          message: 'Speech window processed locally; raw PCM removed.',
        ),
      );
    }
  }

  Future<void> _destroyEphemeralFile(File? file) async {
    if (file == null || !file.existsSync()) return;
    try {
      final length = file.lengthSync();
      final handle = file.openSync(mode: FileMode.write);
      try {
        final zeroBlock = Uint8List(64 * 1024);
        var remaining = length;
        while (remaining > 0) {
          final count = remaining > zeroBlock.length
              ? zeroBlock.length
              : remaining;
          handle.writeFromSync(zeroBlock, 0, count);
          remaining -= count;
        }
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
    } catch (_) {
      // Flash filesystems and copy-on-write storage cannot guarantee overwrite.
    }
    try {
      file.deleteSync();
    } catch (_) {
      // Best-effort deletion; no transcript generation continues after failure.
    }
  }

  void _emit(SpeechContextState value) {
    _current = value;
    if (!_states.isClosed) _states.add(value);
  }

  Future<void> deactivate() async {
    await _recognizer?.close();
    _recognizer = null;
    _emit(
      SpeechContextState(
        installed: _current.installed,
        active: false,
        busy: false,
        modelProgress: _current.modelProgress,
        tokenizerProgress: _current.tokenizerProgress,
        message: 'Speech recognizer inactive.',
      ),
    );
  }

  Future<void> close() async {
    await _recognizer?.close();
    _recognizer = null;
    await _states.close();
  }
}
