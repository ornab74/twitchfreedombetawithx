import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:oqs/oqs.dart';

import 'vault.dart';

/// Versioned public recipient material for the hybrid KEM-DEM construction.
final class HybridPublicIdentity {
  const HybridPublicIdentity({
    required this.mlKemPublicKey,
    required this.x25519PublicKey,
  });

  final Uint8List mlKemPublicKey;
  final Uint8List x25519PublicKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'pqKem': HybridPqCrypto.mlKemAlgorithm,
    'classicalKem': 'X25519',
    'mlKemPublicKey': base64UrlEncode(mlKemPublicKey),
    'x25519PublicKey': base64UrlEncode(x25519PublicKey),
  };

  static HybridPublicIdentity fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 ||
        json['pqKem'] != HybridPqCrypto.mlKemAlgorithm ||
        json['classicalKem'] != 'X25519') {
      throw const FormatException('Unsupported hybrid public identity.');
    }
    return HybridPublicIdentity(
      mlKemPublicKey: HybridPqCrypto._decode(json['mlKemPublicKey'], 1184),
      x25519PublicKey: HybridPqCrypto._decode(json['x25519PublicKey'], 32),
    );
  }
}

final class HybridPrivateIdentity {
  const HybridPrivateIdentity({
    required this.publicIdentity,
    required this.mlKemSecretKey,
    required this.x25519SecretKey,
  });

  final HybridPublicIdentity publicIdentity;
  final Uint8List mlKemSecretKey;
  final Uint8List x25519SecretKey;

  void destroy() {
    mlKemSecretKey.fillRange(0, mlKemSecretKey.length, 0);
    x25519SecretKey.fillRange(0, x25519SecretKey.length, 0);
  }
}

/// A hybrid ML-KEM-768 + X25519 KEM-DEM construction.
///
/// Both independent shared secrets are length-framed and passed through a
/// transcript-bound HKDF-SHA-256. AES-256-GCM then authenticates both the
/// ciphertext and the full algorithm/key transcript. This preserves classical
/// security if ML-KEM fails and post-quantum confidentiality if X25519 fails.
final class HybridPqCrypto {
  HybridPqCrypto({required VaultRepository vault}) : _vault = vault;

  static const String mlKemAlgorithm = 'ML-KEM-768';
  static const String suite =
      'TF-HYBRID-MLKEM768-X25519-HKDFSHA256-AES256GCM-v1';
  static const String _identityType = 'hybrid_pq_identity';
  static const String _identityId = 'device-v1';
  // A liboqs build is not byte-reproducible across compiler/linker versions.
  // Release CI injects the digest of the provider it just built from the
  // pinned source commit. The default is the audited repository build used by
  // local development and tests.
  static const String _linuxX64LibrarySha256 = String.fromEnvironment(
    'TWITCH_FREEDOM_LIBOQS_SHA256',
    defaultValue:
        '6dc25767b485445c20aa33f00a0fcc7c60016f6750f786021cc7a324517fadf9',
  );
  static String? _verifiedBundledLibrary;

  final VaultRepository _vault;
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final AesGcm _aead = AesGcm.with256bits();

  Future<HybridPublicIdentity> ensureDeviceIdentity() async {
    final existing = await _vault.getJson(_identityType, _identityId);
    if (existing != null) {
      return HybridPublicIdentity.fromJson(
        existing['public']! as Map<String, Object?>,
      );
    }
    final identity = await generateIdentity();
    try {
      await _vault.putJson(_identityType, _identityId, <String, Object?>{
        'version': 1,
        'suite': suite,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'public': identity.publicIdentity.toJson(),
        'mlKemSecretKey': base64UrlEncode(identity.mlKemSecretKey),
        'x25519SecretKey': base64UrlEncode(identity.x25519SecretKey),
      });
      return identity.publicIdentity;
    } finally {
      identity.destroy();
    }
  }

  Future<HybridPrivateIdentity> _loadDeviceIdentity() async {
    final record = await _vault.getJson(_identityType, _identityId);
    if (record == null || record['version'] != 1 || record['suite'] != suite) {
      throw StateError('The hybrid device identity is unavailable.');
    }
    final public = HybridPublicIdentity.fromJson(
      Map<String, Object?>.from(record['public']! as Map<Object?, Object?>),
    );
    return HybridPrivateIdentity(
      publicIdentity: public,
      mlKemSecretKey: _decode(record['mlKemSecretKey'], 2400),
      x25519SecretKey: _decode(record['x25519SecretKey'], 32),
    );
  }

  Future<HybridPrivateIdentity> generateIdentity() async {
    final kem = _kem();
    KEMKeyPair? pq;
    SimpleKeyPairData? classical;
    try {
      pq = kem.generateKeyPair();
      classical = await (await _x25519.newKeyPair()).extract();
      final classicalPublic = await classical.extractPublicKey();
      return HybridPrivateIdentity(
        publicIdentity: HybridPublicIdentity(
          mlKemPublicKey: Uint8List.fromList(pq.publicKey),
          x25519PublicKey: Uint8List.fromList(classicalPublic.bytes),
        ),
        mlKemSecretKey: Uint8List.fromList(pq.secretKey),
        x25519SecretKey: Uint8List.fromList(classical.bytes),
      );
    } finally {
      pq?.dispose();
      classical?.destroy();
      kem.dispose();
    }
  }

  Future<Map<String, Object?>> sealFor({
    required HybridPublicIdentity recipient,
    required List<int> cleartext,
    required String context,
  }) async {
    _validateContext(context);
    if (cleartext.length > 16 * 1024 * 1024) {
      throw ArgumentError.value(
        cleartext.length,
        'cleartext',
        'Payload too large.',
      );
    }
    final kem = _kem();
    KEMEncapsulationResult? pq;
    SimpleKeyPairData? ephemeral;
    Uint8List? classicalSecret;
    Uint8List? combined;
    Uint8List? contentKey;
    try {
      if (recipient.mlKemPublicKey.length != kem.publicKeyLength) {
        throw const FormatException('Invalid ML-KEM recipient key length.');
      }
      pq = kem.encapsulate(recipient.mlKemPublicKey);
      ephemeral = await (await _x25519.newKeyPair()).extract();
      final ephemeralPublic = await ephemeral.extractPublicKey();
      classicalSecret = Uint8List.fromList(
        await (await _x25519.sharedSecretKey(
          keyPair: ephemeral,
          remotePublicKey: SimplePublicKey(
            recipient.x25519PublicKey,
            type: KeyPairType.x25519,
          ),
        )).extractBytes(),
      );
      final transcript = _transcript(
        context: context,
        recipient: recipient,
        ephemeralPublic: ephemeralPublic.bytes,
        pqCiphertext: pq.ciphertext,
      );
      combined = _frameSecrets(pq.sharedSecret, classicalSecret);
      contentKey = Uint8List.fromList(
        await (await _hkdf.deriveKey(
          secretKey: SecretKey(combined),
          nonce: transcript,
          info: utf8.encode('$suite\u0000content-key'),
        )).extractBytes(),
      );
      final box = await _aead.encrypt(
        cleartext,
        secretKey: SecretKey(contentKey),
        aad: transcript,
      );
      return <String, Object?>{
        'version': 1,
        'suite': suite,
        'context': context,
        'recipientMlKemPublicKey': base64UrlEncode(recipient.mlKemPublicKey),
        'recipientX25519PublicKey': base64UrlEncode(recipient.x25519PublicKey),
        'ephemeralX25519PublicKey': base64UrlEncode(ephemeralPublic.bytes),
        'mlKemCiphertext': base64UrlEncode(pq.ciphertext),
        'aeadEnvelope': base64UrlEncode(box.concatenation()),
      };
    } finally {
      pq?.dispose();
      ephemeral?.destroy();
      _wipe(classicalSecret);
      _wipe(combined);
      _wipe(contentKey);
      kem.dispose();
    }
  }

  Future<Uint8List> openDeviceEnvelope(Map<String, Object?> envelope) async {
    final identity = await _loadDeviceIdentity();
    try {
      return await openWith(identity: identity, envelope: envelope);
    } finally {
      identity.destroy();
    }
  }

  Future<Uint8List> openWith({
    required HybridPrivateIdentity identity,
    required Map<String, Object?> envelope,
  }) async {
    if (envelope['version'] != 1 || envelope['suite'] != suite) {
      throw const FormatException('Unsupported hybrid envelope.');
    }
    final context = envelope['context']?.toString() ?? '';
    _validateContext(context);
    final recipient = HybridPublicIdentity(
      mlKemPublicKey: _decode(envelope['recipientMlKemPublicKey'], 1184),
      x25519PublicKey: _decode(envelope['recipientX25519PublicKey'], 32),
    );
    if (!_constantTimeEqual(
          recipient.mlKemPublicKey,
          identity.publicIdentity.mlKemPublicKey,
        ) ||
        !_constantTimeEqual(
          recipient.x25519PublicKey,
          identity.publicIdentity.x25519PublicKey,
        )) {
      throw const FormatException(
        'Envelope recipient does not match this identity.',
      );
    }
    final ephemeralPublic = _decode(envelope['ephemeralX25519PublicKey'], 32);
    final pqCiphertext = _decode(envelope['mlKemCiphertext'], 1088);
    final aeadEnvelope = _decodeRange(
      envelope['aeadEnvelope'],
      28,
      16 * 1024 * 1024 + 28,
    );
    final kem = _kem();
    Uint8List? pqSecret;
    Uint8List? classicalSecret;
    Uint8List? combined;
    Uint8List? contentKey;
    SimpleKeyPairData? classicalKeyPair;
    try {
      pqSecret = kem.decapsulate(pqCiphertext, identity.mlKemSecretKey);
      classicalKeyPair = SimpleKeyPairData(
        identity.x25519SecretKey,
        publicKey: SimplePublicKey(
          identity.publicIdentity.x25519PublicKey,
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
      classicalSecret = Uint8List.fromList(
        await (await _x25519.sharedSecretKey(
          keyPair: classicalKeyPair,
          remotePublicKey: SimplePublicKey(
            ephemeralPublic,
            type: KeyPairType.x25519,
          ),
        )).extractBytes(),
      );
      final transcript = _transcript(
        context: context,
        recipient: recipient,
        ephemeralPublic: ephemeralPublic,
        pqCiphertext: pqCiphertext,
      );
      combined = _frameSecrets(pqSecret, classicalSecret);
      contentKey = Uint8List.fromList(
        await (await _hkdf.deriveKey(
          secretKey: SecretKey(combined),
          nonce: transcript,
          info: utf8.encode('$suite\u0000content-key'),
        )).extractBytes(),
      );
      final box = SecretBox.fromConcatenation(
        aeadEnvelope,
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      return Uint8List.fromList(
        await _aead.decrypt(
          box,
          secretKey: SecretKey(contentKey),
          aad: transcript,
        ),
      );
    } finally {
      _wipe(pqSecret);
      _wipe(classicalSecret);
      _wipe(combined);
      _wipe(contentKey);
      classicalKeyPair?.destroy();
      kem.dispose();
    }
  }

  KEM _kem() {
    _configureBundledLibrary();
    final kem = KEM.create(mlKemAlgorithm);
    if (kem == null ||
        kem.claimedNistLevel < 3 ||
        !kem.isIndCcaSecure ||
        kem.publicKeyLength != 1184 ||
        kem.secretKeyLength != 2400 ||
        kem.ciphertextLength != 1088 ||
        kem.sharedSecretLength != 32) {
      kem?.dispose();
      throw StateError(
        'A conforming native ML-KEM-768 implementation is unavailable.',
      );
    }
    return kem;
  }

  void _configureBundledLibrary() {
    if (!Platform.isLinux) return;
    final candidates = <File>[
      File('${File(Platform.resolvedExecutable).parent.path}/lib/liboqs.so'),
      // flutter_tester runs from the SDK rather than the application bundle.
      // The repository provider is accepted only after the same pinned digest
      // verification, so tests exercise real ML-KEM without a weak fallback.
      File('native/linux/liboqs.so').absolute,
    ];
    final bundled = candidates.where((file) => file.existsSync()).firstOrNull;
    if (bundled != null) {
      final path = bundled.absolute.path;
      if (_verifiedBundledLibrary != path) {
        final digest = hashes.sha256
            .convert(bundled.readAsBytesSync())
            .toString();
        if (digest != _linuxX64LibrarySha256) {
          throw StateError(
            'Bundled ML-KEM provider failed integrity verification.',
          );
        }
        // The dynamic provider is loaded once per process. Re-reading and
        // hashing the same shared object for every encapsulation added CPU and
        // UI-isolate I/O without strengthening the already-loaded library.
        _verifiedBundledLibrary = path;
      }
      LibOQSLoader.customPaths = LibraryPaths(
        linuxX64: bundled.path,
        linuxArm64: bundled.path,
      );
    }
  }

  Uint8List _transcript({
    required String context,
    required HybridPublicIdentity recipient,
    required List<int> ephemeralPublic,
    required List<int> pqCiphertext,
  }) => Uint8List.fromList(
    hashes.sha256.convert(<int>[
      ..._frame(utf8.encode(suite)),
      ..._frame(utf8.encode(context)),
      ..._frame(recipient.mlKemPublicKey),
      ..._frame(recipient.x25519PublicKey),
      ..._frame(ephemeralPublic),
      ..._frame(pqCiphertext),
    ]).bytes,
  );

  Uint8List _frameSecrets(List<int> pq, List<int> classical) =>
      Uint8List.fromList(<int>[
        ..._frame(utf8.encode('$suite\u0000ML-KEM')),
        ..._frame(pq),
        ..._frame(utf8.encode('$suite\u0000X25519')),
        ..._frame(classical),
      ]);

  List<int> _frame(List<int> value) {
    final length = ByteData(4)..setUint32(0, value.length, Endian.big);
    return <int>[...length.buffer.asUint8List(), ...value];
  }

  void _validateContext(String value) {
    if (value.isEmpty ||
        value.length > 200 ||
        value.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw const FormatException('Hybrid envelope context is invalid.');
    }
  }

  static Uint8List _decode(Object? value, int expectedLength) {
    final bytes = _decodeRange(value, expectedLength, expectedLength);
    return bytes;
  }

  static Uint8List _decodeRange(Object? value, int minimum, int maximum) {
    if (value is! String || value.length > ((maximum * 4 + 2) ~/ 3) + 4) {
      throw const FormatException('Invalid hybrid envelope encoding.');
    }
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      if (bytes.length < minimum || bytes.length > maximum)
        throw const FormatException();
      return Uint8List.fromList(bytes);
    } catch (_) {
      throw const FormatException('Invalid hybrid envelope field.');
    }
  }

  bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  void _wipe(Uint8List? value) => value?.fillRange(0, value.length, 0);
}

extension _FirstFileOrNull on Iterable<File> {
  File? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
