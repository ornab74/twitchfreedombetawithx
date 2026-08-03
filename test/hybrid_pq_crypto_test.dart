import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/secure_log.dart';
import 'package:twitch_freedom_ultra/security/hybrid_pq_crypto.dart';
import 'package:twitch_freedom_ultra/security/vault.dart';

void main() {
  late HybridPqCrypto hybrid;
  final nativePqSkip = Platform.isLinux
      ? false
      : 'The pinned native liboqs provider is currently bundled on Linux only.';

  setUp(() {
    hybrid = HybridPqCrypto(vault: VaultRepository(log: SecureLog()));
  });

  test('ML-KEM-768 + X25519 hybrid envelope round-trips', () async {
    final identity = await hybrid.generateIdentity();
    try {
      final envelope = await hybrid.sealFor(
        recipient: identity.publicIdentity,
        cleartext: utf8.encode('private agent context'),
        context: 'agent-context-export/v1',
      );
      final opened = await hybrid.openWith(
        identity: identity,
        envelope: envelope,
      );
      expect(utf8.decode(opened), 'private agent context');
      expect(envelope['suite'], HybridPqCrypto.suite);
    } finally {
      identity.destroy();
    }
  }, skip: nativePqSkip);

  test('hybrid transcript tampering fails closed', () async {
    final identity = await hybrid.generateIdentity();
    try {
      final envelope = await hybrid.sealFor(
        recipient: identity.publicIdentity,
        cleartext: utf8.encode('sensitive'),
        context: 'agent-context-export/v1',
      );
      final tampered = <String, Object?>{
        ...envelope,
        'context': 'agent-context-export/v2',
      };
      await expectLater(
        hybrid.openWith(identity: identity, envelope: tampered),
        throwsA(anything),
      );
    } finally {
      identity.destroy();
    }
  }, skip: nativePqSkip);
}
