import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:convert/convert.dart' as convert;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import '../security/vault.dart';
import 'x_models.dart';

final class XMediaStore {
  XMediaStore({required VaultRepository vault, required SecureLog log})
    : _vault = vault,
      _log = log;

  static const int maximumMediaBytes = 1024 * 1024 * 1024;
  static const int _chunkBytes = 1024 * 1024;
  static const List<int> _magic = <int>[0x58, 0x46, 0x56, 0x31]; // XFV1
  static const Set<String> _trustedHosts = <String>{
    'pbs.twimg.com',
    'video.twimg.com',
  };

  final VaultRepository _vault;
  final SecureLog _log;
  final AesGcm _aes = AesGcm.with256bits();
  final Random _random = Random.secure();
  final Uuid _uuid = const Uuid();

  static bool isTrustedMediaUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      _trustedHosts.contains(uri.host.toLowerCase());

  Future<List<XStoredMedia>> list() async {
    final rows = await _vault.getAllJson('x_media');
    return rows.map(XStoredMedia.fromJson).toList();
  }

  Future<AppResult<XStoredMedia>> download({
    required Uri url,
    required String postId,
    required String mediaKey,
    required String contentType,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!isTrustedMediaUri(url)) {
      return const AppError<XStoredMedia>(
        AppFailure(
          'x_media_host_rejected',
          'Only official X media hosts are allowed.',
        ),
      );
    }
    HttpClient? client;
    RandomAccessFile? output;
    File? partial;
    try {
      final id = _uuid.v4();
      final directory = await _directory();
      final finalFile = File(p.join(directory.path, '$id.v1.xfv'));
      partial = File('${finalFile.path}.partial');
      if (partial.existsSync()) partial.deleteSync();
      client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
      client.badCertificateCallback = (_, __, ___) => false;
      var current = url;
      HttpClientResponse? response;
      for (
        var redirects = 0;
        redirects <= AppConfig.maxRedirects;
        redirects++
      ) {
        if (!isTrustedMediaUri(current))
          throw const HttpException('Untrusted media URL.');
        final request = await client.getUrl(current);
        request.headers.set(HttpHeaders.acceptHeader, 'video/mp4,image/*');
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'TwitchFreedom/${AppConfig.appVersion}',
        );
        request.followRedirects = false;
        response = await request.close().timeout(AppConfig.networkTimeout);
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null)
          throw const HttpException('Redirect missing location.');
        current = current.resolve(location);
      }
      if (response == null || response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Media download returned HTTP ${response?.statusCode}.',
        );
      }
      final declared = response.contentLength;
      if (declared > maximumMediaBytes)
        throw const FileSystemException('Media exceeds size limit.');

      final fileKey = _randomBytes(32);
      final digestSink = convert.AccumulatorSink<crypto.Digest>();
      final hasher = crypto.sha256.startChunkedConversion(digestSink);
      output = partial.openSync(mode: FileMode.write);
      output.writeFromSync(_magic);
      var received = 0;
      var chunkIndex = 0;
      var pending = BytesBuilder(copy: false);
      Future<void> sealPending() async {
        final clear = pending.takeBytes();
        if (clear.isEmpty) return;
        final box = await _aes.encrypt(
          clear,
          secretKey: SecretKey(fileKey),
          aad: utf8.encode('xfv1:$id:$chunkIndex'),
        );
        final envelope = box.concatenation();
        final size = ByteData(4)..setUint32(0, envelope.length, Endian.big);
        output!.writeFromSync(size.buffer.asUint8List());
        output!.writeFromSync(envelope);
        chunkIndex++;
      }

      await for (final incoming in response.timeout(AppConfig.networkTimeout)) {
        received += incoming.length;
        if (received > maximumMediaBytes)
          throw const FileSystemException('Media exceeded size limit.');
        hasher.add(incoming);
        pending.add(incoming);
        if (pending.length >= _chunkBytes) await sealPending();
        onProgress?.call(received, declared);
      }
      await sealPending();
      hasher.close();
      output.flushSync();
      output.closeSync();
      output = null;
      partial.renameSync(finalFile.path);
      _harden(finalFile);
      final extension = contentType == 'video/mp4' ? 'mp4' : 'jpg';
      final stored = XStoredMedia(
        id: id,
        postId: postId,
        mediaKey: mediaKey,
        filename: 'x-$postId-$mediaKey.$extension',
        contentType: contentType,
        byteLength: received,
        chunkCount: chunkIndex,
        sha256: digestSink.events.single.toString(),
        createdAt: DateTime.now(),
        keyVersion: 1,
      );
      await _vault.putJson('x_media', id, <String, Object?>{
        ...stored.toJson(),
        'fileKey': base64UrlEncode(fileKey),
      });
      _wipe(fileKey);
      _log.info(
        'Stored authenticated encrypted X media $id ($received bytes).',
      );
      return AppSuccess<XStoredMedia>(stored);
    } on TimeoutException catch (error) {
      return AppError<XStoredMedia>(
        AppFailure(
          'x_media_timeout',
          'The media download timed out.',
          cause: error,
        ),
      );
    } catch (error) {
      _log.warning('Encrypted X media download failed: $error');
      return AppError<XStoredMedia>(
        AppFailure(
          'x_media_download_failed',
          'Could not securely store that media.',
          cause: error,
        ),
      );
    } finally {
      output?.closeSync();
      client?.close(force: true);
      if (partial != null && partial.existsSync()) partial.deleteSync();
    }
  }

  Future<void> delete(XStoredMedia media) async {
    await _vault.delete('x_media', media.id); // Cryptographic erasure first.
    await _vault.purgeDeletedPages();
    final file = File(
      p.join((await _directory()).path, '${media.id}.v${media.keyVersion}.xfv'),
    );
    if (file.existsSync()) file.deleteSync();
    _log.info('Cryptographically erased X media ${media.id}.');
  }

  Future<AppResult<int>> rotateAll() async {
    try {
      final rows = await _vault.getAllJson('x_media');
      var rotated = 0;
      for (final row in rows) {
        final media = XStoredMedia.fromJson(row);
        final oldKey = Uint8List.fromList(
          base64Url.decode(row['fileKey']! as String),
        );
        final newKey = _randomBytes(32);
        final directory = await _directory();
        final source = File(
          p.join(directory.path, '${media.id}.v${media.keyVersion}.xfv'),
        );
        final replacement = File(
          p.join(directory.path, '${media.id}.v${media.keyVersion + 1}.xfv'),
        );
        await _reencrypt(
          source,
          replacement,
          media.id,
          oldKey,
          newKey,
          media.chunkCount,
        );
        _harden(replacement);
        await _vault.putJson('x_media', media.id, <String, Object?>{
          ...media.toJson(),
          'keyVersion': media.keyVersion + 1,
          'fileKey': base64UrlEncode(newKey),
        });
        await _vault.purgeDeletedPages();
        if (source.existsSync()) source.deleteSync();
        _wipe(oldKey);
        _wipe(newKey);
        rotated++;
      }
      return AppSuccess<int>(rotated);
    } catch (error) {
      return AppError<int>(
        AppFailure(
          'x_media_rotation_failed',
          'Media-key rotation did not complete.',
          cause: error,
        ),
      );
    }
  }

  Future<void> _reencrypt(
    File source,
    File target,
    String id,
    Uint8List oldKey,
    Uint8List newKey,
    int expectedChunks,
  ) async {
    if (target.existsSync()) target.deleteSync();
    final input = source.openSync();
    final output = target.openSync(mode: FileMode.write);
    var committed = false;
    try {
      if (!_equal(input.readSync(4), _magic))
        throw const FormatException('Invalid X media container.');
      output.writeFromSync(_magic);
      for (var index = 0; index < expectedChunks; index++) {
        final sizeBytes = input.readSync(4);
        if (sizeBytes.length != 4)
          throw const FormatException('Truncated container.');
        final size = ByteData.sublistView(sizeBytes).getUint32(0, Endian.big);
        final envelope = input.readSync(size);
        if (envelope.length != size)
          throw const FormatException('Truncated encrypted chunk.');
        final oldBox = SecretBox.fromConcatenation(
          envelope,
          nonceLength: _aes.nonceLength,
          macLength: _aes.macAlgorithm.macLength,
        );
        final clear = await _aes.decrypt(
          oldBox,
          secretKey: SecretKey(oldKey),
          aad: utf8.encode('xfv1:$id:$index'),
        );
        final newBox = await _aes.encrypt(
          clear,
          secretKey: SecretKey(newKey),
          aad: utf8.encode('xfv1:$id:$index'),
        );
        final next = newBox.concatenation();
        final nextSize = ByteData(4)..setUint32(0, next.length, Endian.big);
        output.writeFromSync(nextSize.buffer.asUint8List());
        output.writeFromSync(next);
      }
      output.flushSync();
      committed = true;
    } finally {
      input.closeSync();
      output.closeSync();
      if (!committed && target.existsSync()) target.deleteSync();
    }
  }

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'TwitchFreedom', 'x-media'),
    );
    directory.createSync(recursive: true);
    if (!Platform.isWindows)
      Process.runSync('chmod', <String>['700', directory.path]);
    return directory;
  }

  Uint8List _randomBytes(int count) => Uint8List.fromList(
    List<int>.generate(count, (_) => _random.nextInt(256)),
  );
  void _wipe(Uint8List value) => value.fillRange(0, value.length, 0);
  bool _equal(List<int> a, List<int> b) =>
      a.length == b.length &&
      List<int>.generate(
            a.length,
            (index) => a[index] ^ b[index],
          ).fold(0, (x, y) => x | y) ==
          0;
  void _harden(File file) {
    if (!Platform.isWindows)
      Process.runSync('chmod', <String>['600', file.path]);
  }
}
