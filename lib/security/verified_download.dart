import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:convert/convert.dart' as convert;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';

final class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});
  final int received;
  final int total;
  double get fraction =>
      total <= 0 ? 0 : (received / total).clamp(0.0, 1.0).toDouble();
}

final class VerifiedDownloadService {
  VerifiedDownloadService({required SecureLog log}) : _log = log;
  final SecureLog _log;

  Future<AppResult<File>> download({
    required Uri url,
    required String filename,
    required String expectedSha256,
    required int maximumBytes,
    void Function(DownloadProgress progress)? onProgress,
    Map<String, String> headers = const <String, String>{},
    Directory? destinationDirectory,
  }) async {
    HttpClient? client;
    IOSink? sink;
    File? partialFile;
    var committed = false;
    try {
      if (url.scheme != 'https') {
        return const AppError<File>(
          AppFailure('insecure_download_url', 'Model downloads require HTTPS.'),
        );
      }
      final support = destinationDirectory == null
          ? await getApplicationSupportDirectory()
          : null;
      final directory =
          destinationDirectory ??
          Directory(p.join(support!.path, 'TwitchFreedom', 'models'));
      directory.createSync(recursive: true);
      final finalFile = File(p.join(directory.path, filename));
      final partial = File('${finalFile.path}.partial');
      partialFile = partial;
      if (partial.existsSync()) partial.deleteSync();

      client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
      client.badCertificateCallback = (_, __, ___) => false;
      var current = url;
      HttpClientResponse? response;
      for (var redirect = 0; redirect <= AppConfig.maxRedirects; redirect++) {
        final request = await client.getUrl(current);
        headers.forEach(request.headers.set);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'TwitchFreedom/${AppConfig.appVersion}',
        );
        request.followRedirects = false;
        response = await request.close().timeout(AppConfig.networkTimeout);
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null)
          throw const HttpException('Redirect without location.');
        current = current.resolve(location);
        if (current.scheme != 'https')
          throw const HttpException('Redirect downgraded from HTTPS.');
      }
      if (response == null || response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed with HTTP ${response?.statusCode}.',
        );
      }
      final declared = response.contentLength;
      if (declared > maximumBytes)
        throw const FileSystemException(
          'Remote artifact exceeds configured size ceiling.',
        );

      sink = partial.openWrite(mode: FileMode.writeOnly);
      final digestSink = convert.AccumulatorSink<crypto.Digest>();
      final hasher = crypto.sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (received > maximumBytes)
          throw const FileSystemException(
            'Download exceeded configured size ceiling.',
          );
        sink.add(chunk);
        hasher.add(chunk);
        onProgress?.call(
          DownloadProgress(
            received: received,
            total: declared > 0 ? declared : maximumBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      final actual = digestSink.events.single.toString().toLowerCase();
      if (actual != expectedSha256.toLowerCase()) {
        partial.deleteSync();
        return AppError<File>(
          AppFailure(
            'digest_mismatch',
            'Downloaded artifact failed SHA-256 verification. Expected $expectedSha256, received $actual.',
          ),
        );
      }
      if (finalFile.existsSync()) finalFile.deleteSync();
      partial.renameSync(finalFile.path);
      committed = true;
      if (!Platform.isWindows) {
        Process.runSync('chmod', <String>['600', finalFile.path]);
      }
      _log.info(
        'Verified and installed artifact $filename with SHA-256 $actual.',
      );
      return AppSuccess<File>(finalFile);
    } on TimeoutException catch (error) {
      return AppError<File>(
        AppFailure(
          'download_timeout',
          'The download timed out.',
          cause: error,
          retryable: true,
        ),
      );
    } catch (error) {
      return AppError<File>(
        AppFailure(
          'download_failed',
          'The verified download could not complete.',
          cause: error,
          retryable: true,
        ),
      );
    } finally {
      await sink?.close();
      client?.close(force: true);
      if (!committed && partialFile != null && partialFile.existsSync()) {
        partialFile.deleteSync();
      }
    }
  }

  Future<AppResult<File>> installGemma({
    void Function(DownloadProgress progress)? onProgress,
  }) {
    return download(
      url: AppConfig.gemmaModelUrl,
      filename: 'gemma-4-E2B-it.litertlm',
      expectedSha256: AppConfig.gemmaModelSha256,
      maximumBytes: 3 * 1024 * 1024 * 1024,
      onProgress: onProgress,
    );
  }

  static String canonicalManifest(Map<String, Object?> manifest) {
    final keys = manifest.keys.toList()..sort();
    return jsonEncode(<String, Object?>{
      for (final key in keys) key: manifest[key],
    });
  }
}
