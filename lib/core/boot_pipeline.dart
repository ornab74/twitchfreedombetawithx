import 'dart:async';

import 'secure_log.dart';

enum BootStage {
  platformPolicy,
  scheduler,
  vaultProbe,
  rememberedUnlock,
  stateHydration,
  modelAttestation,
  speechAttestation,
  ready,
}

final class BootStep {
  const BootStep({
    required this.stage,
    required this.action,
    this.timeout = const Duration(seconds: 30),
    this.required = true,
  });

  final BootStage stage;
  final Duration timeout;
  final bool required;
  final Future<void> Function() action;
}

final class BootPipeline {
  BootPipeline({required SecureLog log}) : _log = log;

  final SecureLog _log;

  Future<void> run(
    List<BootStep> steps, {
    void Function(BootStage stage)? onStage,
  }) async {
    for (final step in steps) {
      onStage?.call(step.stage);
      _log.info('Boot stage ${step.stage.name} started.');
      try {
        await step.action().timeout(step.timeout);
        _log.info('Boot stage ${step.stage.name} completed.');
      } catch (cause) {
        _log.error('Boot stage ${step.stage.name} failed: $cause');
        if (step.required) rethrow;
      }
    }
  }
}
