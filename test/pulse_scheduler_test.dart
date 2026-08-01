import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/pulse_scheduler.dart';
import 'package:twitch_freedom_ultra/core/secure_log.dart';

void main() {
  test('coalesces duplicate single-flight work', () async {
    final scheduler = PulseScheduler(log: SecureLog())..start();
    scheduler.updateSignals(const PulseSignals(vaultUnlocked: true));
    var executions = 0;

    Future<int> enqueue() => scheduler.schedule<int>(
      PulseTaskSpec<int>(
        key: 'same-work',
        lane: PulseLane.interactive,
        action: (_) async {
          executions += 1;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 7;
        },
      ),
    );

    final values = await Future.wait<int>(<Future<int>>[enqueue(), enqueue()]);
    expect(values, <int>[7, 7]);
    expect(executions, 1);
    await scheduler.close();
  });

  test('serializes AI lane tasks', () async {
    final scheduler = PulseScheduler(log: SecureLog())..start();
    scheduler.updateSignals(
      const PulseSignals(vaultUnlocked: true, modelReady: true),
    );
    var active = 0;
    var maximumActive = 0;

    Future<void> enqueue(String key) => scheduler.schedule<void>(
      PulseTaskSpec<void>(
        key: key,
        lane: PulseLane.ai,
        requiresModel: true,
        action: (_) async {
          active += 1;
          if (active > maximumActive) maximumActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 25));
          active -= 1;
        },
      ),
    );

    await Future.wait<void>(<Future<void>>[
      enqueue('ai-a'),
      enqueue('ai-b'),
      enqueue('ai-c'),
    ]);
    expect(maximumActive, 1);
    await scheduler.close();
  });

  test('vault-gated task waits until unlock signal', () async {
    final scheduler = PulseScheduler(log: SecureLog())..start();
    final completer = Completer<void>();
    final future = scheduler.schedule<void>(
      PulseTaskSpec<void>(
        key: 'vault-task',
        lane: PulseLane.maintenance,
        requiresVault: true,
        action: (_) async => completer.complete(),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(completer.isCompleted, isFalse);
    scheduler.updateSignals(const PulseSignals(vaultUnlocked: true));
    await future;
    expect(completer.isCompleted, isTrue);
    await scheduler.close();
  });
}
