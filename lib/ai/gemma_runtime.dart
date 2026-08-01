import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide DownloadProgress;
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
import '../core/models.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import '../security/vault.dart';
import '../security/verified_download.dart';

final class GemmaRuntimeState {
  const GemmaRuntimeState({
    required this.installed,
    required this.loaded,
    required this.busy,
    required this.progress,
    this.message = '',
  });
  final bool installed;
  final bool loaded;
  final bool busy;
  final double progress;
  final String message;
}

/// One loaded Gemma 4 E2B model with isolated role chats. Inference is serialized
/// to avoid accelerator contention and mobile OOMs.
final class GemmaRuntime {
  GemmaRuntime({required VaultRepository vault, required SecureLog log})
    : _vault = vault,
      _log = log,
      _downloader = VerifiedDownloadService(log: log);

  final VaultRepository _vault;
  final SecureLog _log;
  final VerifiedDownloadService _downloader;
  static const LiteRtLmEngine _engine = LiteRtLmEngine();
  final StreamController<GemmaRuntimeState> _state =
      StreamController<GemmaRuntimeState>.broadcast();
  final Map<AgentRole, InferenceChat> _chats = <AgentRole, InferenceChat>{};
  Future<void> _queue = Future<void>.value();
  InferenceModel? _model;
  String? _loadedModelPath;
  AiBackend? _loadedBackend;
  String _configuredModelDirectory = '';
  String? _configuredModelFile;
  int _generationEpoch = 0;
  GemmaRuntimeState _current = const GemmaRuntimeState(
    installed: false,
    loaded: false,
    busy: false,
    progress: 0,
  );

  Stream<GemmaRuntimeState> get states => _state.stream;
  GemmaRuntimeState get current => _current;
  bool get isReady => _model != null;
  String get configuredModelDirectory => _configuredModelDirectory;

  void configureModelDirectory(String path) {
    final value = path.trim();
    if (value.toLowerCase().endsWith('.litertlm')) {
      _configuredModelFile = File(value).absolute.path;
      _configuredModelDirectory = File(value).parent.absolute.path;
    } else {
      _configuredModelFile = null;
      _configuredModelDirectory = value;
    }
  }

  static PreferredBackend preferredBackend(AiBackend backend) =>
      switch (backend) {
        AiBackend.cpuOnly => PreferredBackend.cpu,
        AiBackend.gpuOnly || AiBackend.gpuFirst => PreferredBackend.gpu,
        AiBackend.npu => PreferredBackend.npu,
      };

  Future<Directory> _modelDirectory() async {
    if (_configuredModelDirectory.isNotEmpty) {
      final configured = Directory(_configuredModelDirectory).absolute;
      if (!await configured.exists()) await configured.create(recursive: true);
      return configured;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'TwitchFreedom', 'models'),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> resolvedModelDirectoryPath() async =>
      (await _modelDirectory()).absolute.path;

  Future<File> modelFile() async {
    final selected = _configuredModelFile;
    if (selected != null && await File(selected).exists())
      return File(selected);
    final directory = await _modelDirectory();
    final preferred = File(p.join(directory.path, AppConfig.gemmaModelName));
    if (await preferred.exists()) return preferred;
    File? candidate;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.litertlm')) {
        continue;
      }
      if (candidate != null) return preferred;
      candidate = entity;
    }
    return candidate ?? preferred;
  }

  Future<void> refreshInstallationState() async {
    final file = await modelFile();
    final attestation = _vault.isUnlocked
        ? await _vault.getJson('model_attestation', AppConfig.gemmaModelName)
        : null;
    final stat = await _regularFileStat(file);
    final trusted =
        stat != null && _attestationMatches(attestation, file, stat);
    _emit(
      GemmaRuntimeState(
        installed: trusted,
        loaded: _model != null,
        busy: false,
        progress: trusted ? 1 : 0,
      ),
    );
  }

  Future<AppResult<File>> attestConfiguredModel() async {
    if (!_vault.isUnlocked) {
      return const AppError<File>(
        AppFailure(
          'vault_locked',
          'Unlock the vault before selecting a model directory.',
        ),
      );
    }
    try {
      final file = await modelFile();
      final stat = await _regularFileStat(file);
      if (stat == null) {
        return AppError<File>(
          AppFailure(
            'model_missing',
            'No ${AppConfig.gemmaModelName} or single .litertlm model was found in that directory.',
          ),
        );
      }
      final existing = await _vault.getJson(
        'model_attestation',
        AppConfig.gemmaModelName,
      );
      if (_attestationMatches(existing, file, stat)) {
        _emit(
          const GemmaRuntimeState(
            installed: true,
            loaded: false,
            busy: false,
            progress: 1,
            message: 'Unchanged model verified from encrypted attestation.',
          ),
        );
        return AppSuccess<File>(file);
      }
      _emit(
        const GemmaRuntimeState(
          installed: false,
          loaded: false,
          busy: true,
          progress: 0,
          message: 'Verifying selected Gemma model…',
        ),
      );
      final modelPath = file.absolute.path;
      final progressPort = ReceivePort();
      final resultPort = ReceivePort();
      final progressSubscription = progressPort.listen((Object? value) {
        if (value is! int || stat.size <= 0) return;
        final fraction = (value / stat.size).clamp(0.0, .98).toDouble();
        _emit(
          GemmaRuntimeState(
            installed: false,
            loaded: false,
            busy: true,
            progress: fraction,
            message:
                'Verifying selected Gemma model… ${(fraction * 100).round()}%',
          ),
        );
      });
      late String digest;
      try {
        await Isolate.spawn<(String, int, SendPort, SendPort)>(
          _sha256FileWorker,
          (modelPath, stat.size, progressPort.sendPort, resultPort.sendPort),
        );
        final workerResult = await resultPort.first;
        if (workerResult case <String, Object?>{'digest': final String value}) {
          digest = value;
        } else {
          final message = workerResult is Map
              ? workerResult['error']?.toString()
              : workerResult.toString();
          throw StateError(message ?? 'Model verification worker failed.');
        }
      } finally {
        await progressSubscription.cancel();
        progressPort.close();
        resultPort.close();
      }
      final verifiedStat = await _regularFileStat(file);
      if (verifiedStat == null || !_sameFileSnapshot(stat, verifiedStat)) {
        _emit(
          const GemmaRuntimeState(
            installed: false,
            loaded: false,
            busy: false,
            progress: 0,
            message: 'Model changed while it was being verified.',
          ),
        );
        return const AppError<File>(
          AppFailure(
            'model_changed_during_verification',
            'The model changed during verification. Try again after writes finish.',
            retryable: true,
          ),
        );
      }
      if (digest.toLowerCase() != AppConfig.gemmaSha256.toLowerCase()) {
        _emit(
          const GemmaRuntimeState(
            installed: false,
            loaded: false,
            busy: false,
            progress: 0,
            message: 'Selected model failed SHA-256 verification.',
          ),
        );
        return const AppError<File>(
          AppFailure(
            'model_untrusted',
            'The selected model does not match the pinned Gemma artifact.',
          ),
        );
      }
      await _vault.putJson(
        'model_attestation',
        AppConfig.gemmaModelName,
        <String, Object?>{
          ..._attestationIdentity(file, verifiedStat),
          'verifiedAt': DateTime.now().toUtc().toIso8601String(),
          'source': 'user-selected-file',
        },
      );
      _emit(
        const GemmaRuntimeState(
          installed: true,
          loaded: false,
          busy: false,
          progress: 1,
          message: 'Selected Gemma model verified for direct local loading.',
        ),
      );
      return AppSuccess<File>(file);
    } catch (cause) {
      _emit(
        GemmaRuntimeState(
          installed: false,
          loaded: false,
          busy: false,
          progress: 0,
          message: 'Could not use the selected model file: $cause',
        ),
      );
      return AppError<File>(
        AppFailure(
          'model_file_failed',
          'Could not verify or register the selected model file: $cause',
          cause: cause,
        ),
      );
    }
  }

  Future<AppResult<File>> installModel({
    void Function(double progress)? onProgress,
  }) async {
    if (!_vault.isUnlocked)
      return const AppError<File>(
        AppFailure(
          'vault_locked',
          'Unlock the vault before installing the local model.',
        ),
      );
    final destination = await modelFile();
    _emit(
      const GemmaRuntimeState(
        installed: false,
        loaded: false,
        busy: true,
        progress: 0,
        message: 'Downloading verified Gemma model…',
      ),
    );
    var lastProgress = -1.0;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    final result = await _downloader.download(
      url: AppConfig.gemmaModelUri,
      filename: p.basename(destination.path),
      expectedSha256: AppConfig.gemmaSha256,
      maximumBytes: AppConfig.gemmaMaximumBytes,
      destinationDirectory: await _modelDirectory(),
      onProgress: (DownloadProgress value) {
        final progress = value.fraction;
        final now = DateTime.now();
        if (progress < 1 &&
            progress - lastProgress < .005 &&
            now.difference(lastProgressAt) <
                const Duration(milliseconds: 200)) {
          return;
        }
        lastProgress = progress;
        lastProgressAt = now;
        onProgress?.call(progress);
        _emit(
          GemmaRuntimeState(
            installed: false,
            loaded: false,
            busy: true,
            progress: progress,
            message: 'Verifying model download…',
          ),
        );
      },
    );
    return result.fold(
      success: (File file) async {
        final stat = await _regularFileStat(file);
        if (stat == null) {
          return const AppError<File>(
            AppFailure(
              'model_install_invalid',
              'The verified download was not a regular model file.',
            ),
          );
        }
        await _vault.putJson(
          'model_attestation',
          AppConfig.gemmaModelName,
          <String, Object?>{
            ..._attestationIdentity(file, stat),
            'verifiedAt': DateTime.now().toUtc().toIso8601String(),
            'source': AppConfig.gemmaModelUri.toString(),
          },
        );
        _emit(
          const GemmaRuntimeState(
            installed: true,
            loaded: false,
            busy: false,
            progress: 1,
            message: 'Model verified and installed.',
          ),
        );
        return AppSuccess<File>(file);
      },
      failure: (AppFailure failure) async {
        _emit(
          GemmaRuntimeState(
            installed: false,
            loaded: false,
            busy: false,
            progress: 0,
            message: failure.message,
          ),
        );
        return AppError<File>(failure);
      },
    );
  }

  Future<FileStat?> _regularFileStat(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file ? stat : null;
  }

  bool _attestationMatches(
    Map<String, Object?>? attestation,
    File file,
    FileStat stat,
  ) =>
      attestation?['sha256'] == AppConfig.gemmaSha256 &&
      attestation?['bytes'] == stat.size &&
      attestation?['path'] == file.absolute.path &&
      attestation?['modifiedMicros'] == stat.modified.microsecondsSinceEpoch &&
      attestation?['changedMicros'] == stat.changed.microsecondsSinceEpoch;

  Map<String, Object?> _attestationIdentity(File file, FileStat stat) =>
      <String, Object?>{
        'sha256': AppConfig.gemmaSha256,
        'bytes': stat.size,
        'path': file.absolute.path,
        'modifiedMicros': stat.modified.microsecondsSinceEpoch,
        'changedMicros': stat.changed.microsecondsSinceEpoch,
      };

  bool _sameFileSnapshot(FileStat before, FileStat after) =>
      before.type == after.type &&
      before.size == after.size &&
      before.modified == after.modified &&
      before.changed == after.changed;

  Future<AppResult<void>> load(AiBackend backend) async {
    try {
      final constrainedLinux =
          Platform.isLinux &&
          ((Platform.environment['TWITCH_FREEDOM_AI_RENDERER']?.contains(
                    'cpu',
                  ) ??
                  false) ||
              (Platform.environment['TWITCH_FREEDOM_RENDERER']?.contains(
                    'software',
                  ) ??
                  false));
      if (constrainedLinux && backend != AiBackend.cpuOnly) {
        backend = AiBackend.cpuOnly;
        _log.info(
          'Gemma backend constrained to CPU by the Linux workload policy.',
        );
      }
      final file = await modelFile();
      if (!file.existsSync())
        return const AppError<void>(
          AppFailure(
            'model_missing',
            'Install Gemma 4 E2B before enabling AI features.',
          ),
        );
      await refreshInstallationState();
      if (!_current.installed)
        return const AppError<void>(
          AppFailure(
            'model_untrusted',
            'The model failed integrity attestation. Reinstall it.',
          ),
        );
      final absolutePath = file.absolute.path;
      if (_model != null &&
          _loadedModelPath == absolutePath &&
          _loadedBackend == backend) {
        _emit(
          const GemmaRuntimeState(
            installed: true,
            loaded: true,
            busy: false,
            progress: 1,
            message: 'Local model ready.',
          ),
        );
        return const AppSuccess<void>(null);
      }
      if (_model != null) await unload();
      _emit(
        GemmaRuntimeState(
          installed: true,
          loaded: false,
          busy: true,
          progress: 1,
          message: 'Loading local model…',
        ),
      );
      Future<InferenceModel> openWith(PreferredBackend preferred) {
        final spec = InferenceModelSpec(
          name: p.basenameWithoutExtension(file.path),
          modelSource: ModelSource.file(file.absolute.path),
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        );
        return _engine.createModel(
          spec,
          RuntimeConfig(
            maxTokens: 4096,
            modelPath: file.absolute.path,
            preferredBackend: preferred,
            maxConcurrentSessions: 2,
          ),
        );
      }

      if (backend == AiBackend.gpuFirst) {
        try {
          _model = await openWith(PreferredBackend.gpu);
        } catch (gpuCause) {
          _log.warning(
            'GPU-first Gemma load failed; retrying on CPU: $gpuCause',
          );
          _model = await openWith(PreferredBackend.cpu);
        }
      } else {
        _model = await openWith(preferredBackend(backend));
      }
      _loadedModelPath = absolutePath;
      _loadedBackend = backend;
      _chats.clear();
      _emit(
        const GemmaRuntimeState(
          installed: true,
          loaded: true,
          busy: false,
          progress: 1,
          message: 'Local model ready.',
        ),
      );
      return const AppSuccess<void>(null);
    } catch (cause) {
      _log.error('Gemma load failed: $cause');
      _emit(
        GemmaRuntimeState(
          installed: true,
          loaded: false,
          busy: false,
          progress: 1,
          message: '$cause',
        ),
      );
      return AppError<void>(
        AppFailure(
          'model_load_failed',
          'The local model could not be loaded.',
          cause: cause,
        ),
      );
    }
  }

  Future<AppResult<String>> generate({
    required AgentRole role,
    required String systemInstruction,
    required String prompt,
    int maxOutputTokens = 512,
    double temperature = 0.25,
  }) {
    final completer = Completer<AppResult<String>>();
    final requestEpoch = _generationEpoch;
    _queue = _queue.then((_) async {
      if (requestEpoch != _generationEpoch) {
        completer.complete(
          const AppError<String>(
            AppFailure('cancelled', 'Generation was cancelled.'),
          ),
        );
        return;
      }
      final model = _model;
      if (model == null) {
        completer.complete(
          const AppError<String>(
            AppFailure('model_not_loaded', 'Load the local model first.'),
          ),
        );
        return;
      }
      _emit(
        GemmaRuntimeState(
          installed: true,
          loaded: true,
          busy: true,
          progress: 1,
          message: '${role.name} agent running locally…',
        ),
      );
      try {
        // Every prompt already contains its complete bounded context. Reusing
        // the previous chat would append another large JSON batch to history
        // and eventually exhaust the 4096-token KV cache. Recreate only this
        // role's session while retaining isolation between roles.
        final previous = _chats.remove(role);
        await previous?.close();
        while (_chats.length >= 2) {
          final oldestRole = _chats.keys.first;
          final oldest = _chats.remove(oldestRole);
          await oldest?.close();
        }
        final chat = await model.openChat(
          systemInstruction: systemInstruction,
          temperature: temperature,
          topK: 32,
          topP: 0.9,
          maxOutputTokens: maxOutputTokens,
          modelType: ModelType.gemma4,
        );
        _chats[role] = chat;
        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        final output = StringBuffer();
        await for (final response in chat.generateChatResponseAsync()) {
          if (requestEpoch != _generationEpoch) {
            await chat.stopGeneration();
            throw const AppFailure('cancelled', 'Generation was cancelled.');
          }
          if (response is TextResponse) output.write(response.token);
        }
        final text = output.toString().trim();
        if (text.isEmpty)
          throw const FormatException('The model returned no text.');
        completer.complete(AppSuccess<String>(text));
      } catch (cause) {
        _log.warning('${role.name} agent failed: $cause');
        completer.complete(
          cause is AppFailure
              ? AppError<String>(cause)
              : AppError<String>(
                  AppFailure(
                    'generation_failed',
                    'The ${role.name} agent could not complete.',
                    cause: cause,
                    retryable: true,
                  ),
                ),
        );
      } finally {
        _emit(
          const GemmaRuntimeState(
            installed: true,
            loaded: true,
            busy: false,
            progress: 1,
          ),
        );
      }
    });
    return completer.future;
  }

  void cancel() {
    _generationEpoch += 1;
    for (final chat in _chats.values) {
      unawaited(chat.stopGeneration());
    }
  }

  void _emit(GemmaRuntimeState value) {
    _current = value;
    if (!_state.isClosed) _state.add(value);
  }

  Future<void> unload() async {
    final model = _model;
    _model = null;
    _loadedModelPath = null;
    _loadedBackend = null;
    cancel();
    try {
      await _queue;
    } catch (cause) {
      _log.warning('Gemma generation shutdown completed with: $cause');
    }
    final chats = List<InferenceChat>.of(_chats.values);
    _chats.clear();
    for (final chat in chats) {
      try {
        await chat.close();
      } catch (cause) {
        _log.warning('Gemma chat cleanup skipped one session: $cause');
      }
    }
    try {
      await model?.close();
    } catch (cause) {
      _log.warning('Gemma model cleanup completed with: $cause');
    }
    _emit(
      GemmaRuntimeState(
        installed: _current.installed,
        loaded: false,
        busy: false,
        progress: _current.progress,
      ),
    );
  }

  Future<void> close() async {
    await unload();
    await _state.close();
  }
}

Future<String> _sha256FileWithProgress(
  String path,
  int expectedBytes,
  SendPort progressPort,
) async {
  const reportEveryBytes = 64 * 1024 * 1024;
  var processed = 0;
  var lastReported = 0;
  final measured = File(path).openRead().map<List<int>>((List<int> chunk) {
    processed += chunk.length;
    if (processed - lastReported >= reportEveryBytes ||
        processed >= expectedBytes) {
      lastReported = processed;
      progressPort.send(processed);
    }
    return chunk;
  });
  final digest = await crypto.sha256.bind(measured).first;
  if (processed > lastReported) progressPort.send(processed);
  return digest.toString();
}

Future<void> _sha256FileWorker(
  (String, int, SendPort, SendPort) request,
) async {
  final (path, expectedBytes, progressPort, resultPort) = request;
  try {
    final digest = await _sha256FileWithProgress(
      path,
      expectedBytes,
      progressPort,
    );
    resultPort.send(<String, Object?>{'digest': digest});
  } catch (cause) {
    resultPort.send(<String, Object?>{'error': cause.toString()});
  }
}
