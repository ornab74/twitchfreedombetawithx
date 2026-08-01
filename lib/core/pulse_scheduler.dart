import 'dart:async';
import 'dart:math';

import 'secure_log.dart';

enum PulseLane { realtime, interactive, network, ai, maintenance }

enum PulseTaskState { queued, deferred, running, succeeded, failed, cancelled }

final class PulseSignals {
  const PulseSignals({
    this.vaultUnlocked = false,
    this.playbackActive = false,
    this.appVisible = true,
    this.modelReady = false,
    this.chatMessagesPerMinute = 0,
    this.resourcePressure = 0,
  });

  final bool vaultUnlocked;
  final bool playbackActive;
  final bool appVisible;
  final bool modelReady;
  final int chatMessagesPerMinute;
  final double resourcePressure;

  PulseSignals copyWith({
    bool? vaultUnlocked,
    bool? playbackActive,
    bool? appVisible,
    bool? modelReady,
    int? chatMessagesPerMinute,
    double? resourcePressure,
  }) {
    return PulseSignals(
      vaultUnlocked: vaultUnlocked ?? this.vaultUnlocked,
      playbackActive: playbackActive ?? this.playbackActive,
      appVisible: appVisible ?? this.appVisible,
      modelReady: modelReady ?? this.modelReady,
      chatMessagesPerMinute:
          chatMessagesPerMinute ?? this.chatMessagesPerMinute,
      resourcePressure: (resourcePressure ?? this.resourcePressure)
          .clamp(0, 1)
          .toDouble(),
    );
  }
}

final class PulseRetryPolicy {
  const PulseRetryPolicy({
    this.maxAttempts = 1,
    this.initialDelay = const Duration(seconds: 2),
    this.maximumDelay = const Duration(seconds: 30),
    this.multiplier = 2,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maximumDelay;
  final double multiplier;

  Duration delayForAttempt(int attempt, Random random) {
    final rawMilliseconds =
        initialDelay.inMilliseconds * pow(multiplier, max(0, attempt - 1));
    final int bounded = min(
      maximumDelay.inMilliseconds,
      rawMilliseconds.round(),
    ).toInt();
    final jitter = bounded <= 4
        ? 0
        : random.nextInt(max(1, bounded ~/ 5).toInt());
    return Duration(milliseconds: bounded + jitter);
  }
}

final class PulseTaskSpec<T> {
  const PulseTaskSpec({
    required this.key,
    required this.lane,
    required this.action,
    this.scope = 'global',
    this.affinity = '',
    this.priority = 50,
    this.cost = 10,
    this.notBefore,
    this.deadline,
    this.coalesce = true,
    this.requiresVault = false,
    this.requiresModel = false,
    this.pauseDuringPlayback = false,
    this.retryPolicy = const PulseRetryPolicy(),
  });

  final String key;
  final String scope;
  final PulseLane lane;
  final String affinity;
  final int priority;
  final int cost;
  final DateTime? notBefore;
  final DateTime? deadline;
  final bool coalesce;
  final bool requiresVault;
  final bool requiresModel;
  final bool pauseDuringPlayback;
  final PulseRetryPolicy retryPolicy;
  final Future<T> Function(PulseTaskContext context) action;
}

final class PulseTaskContext {
  const PulseTaskContext({
    required this.id,
    required this.key,
    required this.scope,
    required this.attempt,
    required this.signals,
    required bool Function() isCancelled,
  }) : _isCancelled = isCancelled;

  final String id;
  final String key;
  final String scope;
  final int attempt;
  final PulseSignals signals;
  final bool Function() _isCancelled;

  bool get isCancelled => _isCancelled();

  void throwIfCancelled() {
    if (isCancelled) throw const PulseCancelledException();
  }
}

final class PulseCancelledException implements Exception {
  const PulseCancelledException();

  @override
  String toString() => 'Pulse task cancelled.';
}

final class PulseTaskTelemetry {
  const PulseTaskTelemetry({
    required this.id,
    required this.key,
    required this.scope,
    required this.lane,
    required this.state,
    required this.queuedAt,
    this.startedAt,
    this.finishedAt,
    this.attempt = 0,
    this.message = '',
  });

  final String id;
  final String key;
  final String scope;
  final PulseLane lane;
  final PulseTaskState state;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int attempt;
  final String message;
}

final class PulseSnapshot {
  const PulseSnapshot({
    required this.queued,
    required this.running,
    required this.completed,
    required this.credits,
    required this.signals,
  });

  final int queued;
  final int running;
  final int completed;
  final double credits;
  final PulseSignals signals;
}

final class PulseRecurringHandle {
  PulseRecurringHandle(this._cancel);

  final void Function() _cancel;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

final class PulseScheduler {
  PulseScheduler({required SecureLog log}) : _log = log;

  final SecureLog _log;
  final Random _random = Random();
  final List<_QueuedPulseTask> _queue = <_QueuedPulseTask>[];
  final Map<String, Future<Object?>> _singleFlight =
      <String, Future<Object?>>{};
  final Map<PulseLane, int> _runningByLane = <PulseLane, int>{};
  final Map<String, int> _scopeEpochs = <String, int>{};
  final StreamController<PulseTaskTelemetry> _telemetry =
      StreamController<PulseTaskTelemetry>.broadcast();
  final StreamController<PulseSnapshot> _snapshots =
      StreamController<PulseSnapshot>.broadcast();
  final List<PulseRecurringHandle> _recurring = <PulseRecurringHandle>[];

  PulseSignals _signals = const PulseSignals();
  Timer? _creditTimer;
  bool _closed = false;
  int _sequence = 0;
  int _completed = 0;
  int _running = 0;
  double _credits = 100;
  String _lastAffinity = '';

  static const Map<PulseLane, int> _laneLimits = <PulseLane, int>{
    PulseLane.realtime: 4,
    PulseLane.interactive: 2,
    PulseLane.network: 3,
    PulseLane.ai: 1,
    PulseLane.maintenance: 1,
  };

  Stream<PulseTaskTelemetry> get telemetry => _telemetry.stream;
  Stream<PulseSnapshot> get snapshots => _snapshots.stream;
  PulseSignals get signals => _signals;

  void start() {
    if (_closed || _creditTimer != null) return;
    _creditTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final recovery = _signals.playbackActive ? 10.0 : 18.0;
      final previousCredits = _credits;
      _credits = min(100, _credits + recovery).toDouble();
      if (_queue.isEmpty && _running == 0 && previousCredits == _credits) {
        return;
      }
      _emitSnapshot();
      _pump();
    });
    _log.info('PulseMesh scheduler started with adaptive lane isolation.');
  }

  void updateSignals(PulseSignals value) {
    _signals = value;
    _emitSnapshot();
    _pump();
  }

  Future<T> schedule<T>(PulseTaskSpec<T> spec) {
    if (_closed) {
      return Future<T>.error(StateError('PulseScheduler is closed.'));
    }
    start();
    if (spec.coalesce) {
      final existing = _singleFlight[spec.key];
      if (existing != null)
        return existing.then<T>((Object? value) => value as T);
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final completer = Completer<Object?>();
    final task = _QueuedPulseTask(
      id: id,
      sequence: _sequence,
      key: spec.key,
      scope: spec.scope,
      scopeEpoch: _scopeEpochs[spec.scope] ?? 0,
      lane: spec.lane,
      affinity: spec.affinity,
      basePriority: spec.priority.clamp(0, 100).toInt(),
      cost: spec.cost.clamp(1, 100).toInt(),
      queuedAt: DateTime.now(),
      notBefore: spec.notBefore,
      deadline: spec.deadline,
      requiresVault: spec.requiresVault,
      requiresModel: spec.requiresModel,
      pauseDuringPlayback: spec.pauseDuringPlayback,
      retryPolicy: spec.retryPolicy,
      action: (PulseTaskContext context) async => spec.action(context),
      completer: completer,
    );
    _queue.add(task);
    if (spec.coalesce) _singleFlight[spec.key] = completer.future;
    _emit(task, PulseTaskState.queued);
    _emitSnapshot();
    _pump();
    return completer.future.then<T>((Object? value) => value as T);
  }

  PulseRecurringHandle scheduleAdaptiveRecurring({
    required String key,
    required String scope,
    required PulseLane lane,
    required Duration Function(PulseSignals signals) cadence,
    required Future<void> Function(PulseTaskContext context) action,
    String affinity = '',
    int priority = 40,
    int cost = 15,
    bool requiresVault = false,
    bool requiresModel = false,
    bool pauseDuringPlayback = false,
    bool Function(PulseSignals signals)? enabledWhen,
  }) {
    Timer? timer;
    var cancelled = false;

    void arm() {
      if (cancelled || _closed) return;
      var delay = cadence(_signals);
      if (delay < const Duration(seconds: 1))
        delay = const Duration(seconds: 1);
      timer = Timer(delay, () async {
        if (cancelled || _closed) return;
        if (enabledWhen?.call(_signals) ?? true) {
          try {
            await schedule<void>(
              PulseTaskSpec<void>(
                key: key,
                scope: scope,
                lane: lane,
                affinity: affinity,
                priority: priority,
                cost: cost,
                requiresVault: requiresVault,
                requiresModel: requiresModel,
                pauseDuringPlayback: pauseDuringPlayback,
                retryPolicy: const PulseRetryPolicy(maxAttempts: 1),
                action: action,
              ),
            );
          } catch (cause) {
            _log.warning('Recurring Pulse task $key skipped: $cause');
          }
        }
        arm();
      });
    }

    final handle = PulseRecurringHandle(() {
      cancelled = true;
      timer?.cancel();
    });
    _recurring.add(handle);
    arm();
    return handle;
  }

  void cancelScope(String scope) {
    _scopeEpochs[scope] = (_scopeEpochs[scope] ?? 0) + 1;
    final cancelled = _queue.where((task) => task.scope == scope).toList();
    _queue.removeWhere((task) => task.scope == scope);
    for (final task in cancelled) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(const PulseCancelledException());
      }
      _singleFlight.remove(task.key);
      _emit(task, PulseTaskState.cancelled);
    }
    _emitSnapshot();
  }

  void reopenScope(String scope) {
    _scopeEpochs.putIfAbsent(scope, () => 0);
  }

  void _pump() {
    if (_closed || _queue.isEmpty) return;
    final now = DateTime.now();
    final eligible = _queue.where((task) => _canStart(task, now)).toList();
    if (eligible.isEmpty) return;
    eligible.sort((left, right) {
      final scoreCompare = _score(right, now).compareTo(_score(left, now));
      if (scoreCompare != 0) return scoreCompare;
      return left.sequence.compareTo(right.sequence);
    });

    for (final task in eligible) {
      if (_running >= 4) break;
      if (!_canStart(task, DateTime.now())) continue;
      _queue.remove(task);
      _startTask(task);
    }
    _emitSnapshot();
  }

  bool _canStart(_QueuedPulseTask task, DateTime now) {
    if (task.scopeEpoch != (_scopeEpochs[task.scope] ?? 0)) return false;
    if (task.notBefore != null && now.isBefore(task.notBefore!)) return false;
    if (task.requiresVault && !_signals.vaultUnlocked) return false;
    if (task.requiresModel && !_signals.modelReady) return false;
    if (task.pauseDuringPlayback && _signals.playbackActive) return false;
    final laneRunning = _runningByLane[task.lane] ?? 0;
    if (laneRunning >= (_laneLimits[task.lane] ?? 1)) return false;

    final pressurePenalty = _signals.resourcePressure * 35;
    final effectiveCost =
        task.cost +
        (task.lane == PulseLane.ai && _signals.playbackActive ? 18 : 0) +
        pressurePenalty;
    if (_credits < effectiveCost && task.lane != PulseLane.realtime)
      return false;
    return true;
  }

  double _score(_QueuedPulseTask task, DateTime now) {
    final ageSeconds = now.difference(task.queuedAt).inMilliseconds / 1000;
    final aging = min(35.0, ageSeconds / 3);
    var deadlineBoost = 0.0;
    final deadline = task.deadline;
    if (deadline != null) {
      final remaining = deadline.difference(now).inMilliseconds;
      deadlineBoost = remaining <= 0 ? 80 : max(0, 30 - remaining / 1000);
    }
    final affinityBoost =
        task.affinity.isNotEmpty && task.affinity == _lastAffinity ? 7.0 : 0.0;
    final laneBoost = switch (task.lane) {
      PulseLane.realtime => 30.0,
      PulseLane.interactive => 22.0,
      PulseLane.network => 12.0,
      PulseLane.ai => 7.0,
      PulseLane.maintenance => 0.0,
    };
    final playbackPenalty =
        _signals.playbackActive &&
            (task.lane == PulseLane.ai || task.lane == PulseLane.maintenance)
        ? 14.0
        : 0.0;
    return task.basePriority +
        aging +
        deadlineBoost +
        affinityBoost +
        laneBoost -
        playbackPenalty -
        task.cost / 8;
  }

  void _startTask(_QueuedPulseTask task) {
    task.attempt += 1;
    task.startedAt = DateTime.now();
    _running += 1;
    _runningByLane[task.lane] = (_runningByLane[task.lane] ?? 0) + 1;
    final cost =
        task.cost +
        (task.lane == PulseLane.ai && _signals.playbackActive ? 18 : 0);
    _credits = max(0, _credits - cost).toDouble();
    _lastAffinity = task.affinity;
    _emit(task, PulseTaskState.running);

    final context = PulseTaskContext(
      id: task.id,
      key: task.key,
      scope: task.scope,
      attempt: task.attempt,
      signals: _signals,
      isCancelled: () =>
          task.scopeEpoch != (_scopeEpochs[task.scope] ?? 0) || _closed,
    );

    unawaited(
      Future<void>(() async {
        try {
          context.throwIfCancelled();
          final value = await task.action(context);
          context.throwIfCancelled();
          if (!task.completer.isCompleted) task.completer.complete(value);
          _completed += 1;
          task.finishedAt = DateTime.now();
          _emit(task, PulseTaskState.succeeded);
        } catch (cause, stackTrace) {
          final cancelled =
              cause is PulseCancelledException ||
              task.scopeEpoch != (_scopeEpochs[task.scope] ?? 0) ||
              _closed;
          if (!cancelled && task.attempt < task.retryPolicy.maxAttempts) {
            final delay = task.retryPolicy.delayForAttempt(
              task.attempt,
              _random,
            );
            task.notBefore = DateTime.now().add(delay);
            task.startedAt = null;
            _queue.add(task);
            _emit(
              task,
              PulseTaskState.deferred,
              message:
                  'Retry ${task.attempt + 1} in ${delay.inMilliseconds}ms.',
            );
          } else {
            if (!task.completer.isCompleted) {
              task.completer.completeError(cause, stackTrace);
            }
            task.finishedAt = DateTime.now();
            _emit(
              task,
              cancelled ? PulseTaskState.cancelled : PulseTaskState.failed,
              message: '$cause',
            );
          }
        } finally {
          _running -= 1;
          _runningByLane[task.lane] = max(
            0,
            (_runningByLane[task.lane] ?? 1) - 1,
          ).toInt();
          if (task.completer.isCompleted) {
            // Removing a Future-valued map entry returns the in-flight future;
            // it must keep running, but there is intentionally nothing to await.
            unawaited(_singleFlight.remove(task.key));
          }
          _emitSnapshot();
          _pump();
        }
      }),
    );
  }

  void _emit(
    _QueuedPulseTask task,
    PulseTaskState state, {
    String message = '',
  }) {
    if (_telemetry.isClosed) return;
    _telemetry.add(
      PulseTaskTelemetry(
        id: task.id,
        key: task.key,
        scope: task.scope,
        lane: task.lane,
        state: state,
        queuedAt: task.queuedAt,
        startedAt: task.startedAt,
        finishedAt: task.finishedAt,
        attempt: task.attempt,
        message: message,
      ),
    );
  }

  void _emitSnapshot() {
    if (_snapshots.isClosed) return;
    _snapshots.add(
      PulseSnapshot(
        queued: _queue.length,
        running: _running,
        completed: _completed,
        credits: _credits,
        signals: _signals,
      ),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _creditTimer?.cancel();
    for (final handle in _recurring) {
      handle.cancel();
    }
    for (final task in _queue) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(const PulseCancelledException());
      }
    }
    _queue.clear();
    _singleFlight.clear();
    await _telemetry.close();
    await _snapshots.close();
  }
}

final class _QueuedPulseTask {
  _QueuedPulseTask({
    required this.id,
    required this.sequence,
    required this.key,
    required this.scope,
    required this.scopeEpoch,
    required this.lane,
    required this.affinity,
    required this.basePriority,
    required this.cost,
    required this.queuedAt,
    required this.notBefore,
    required this.deadline,
    required this.requiresVault,
    required this.requiresModel,
    required this.pauseDuringPlayback,
    required this.retryPolicy,
    required this.action,
    required this.completer,
  });

  final String id;
  final int sequence;
  final String key;
  final String scope;
  final int scopeEpoch;
  final PulseLane lane;
  final String affinity;
  final int basePriority;
  final int cost;
  final DateTime queuedAt;
  DateTime? notBefore;
  final DateTime? deadline;
  final bool requiresVault;
  final bool requiresModel;
  final bool pauseDuringPlayback;
  final PulseRetryPolicy retryPolicy;
  final Future<Object?> Function(PulseTaskContext context) action;
  final Completer<Object?> completer;
  DateTime? startedAt;
  DateTime? finishedAt;
  int attempt = 0;
}
