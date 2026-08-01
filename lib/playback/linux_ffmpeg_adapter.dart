import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/result.dart';
import '../core/secure_log.dart';

/// Secure desktop FFmpeg adapter.
///
/// It never invokes a shell, accepts only an absolute executable path from a
/// narrow allowlist (or an explicit absolute override), limits capture time,
/// validates HTTPS input, and writes only to a caller-controlled temporary
/// file. Android and iOS intentionally do not use this adapter.
final class SystemFfmpegAdapter {
  SystemFfmpegAdapter({required SecureLog log}) : _log = log;

  final SecureLog _log;

  Future<String?> resolveExecutable() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return null;
    }

    final override = Platform.environment['TWITCH_FREEDOM_FFMPEG_PATH'];
    if (override != null && override.trim().isNotEmpty) {
      final candidate = File(override.trim());
      if (p.isAbsolute(candidate.path) &&
          candidate.existsSync() &&
          _hasExpectedName(candidate.path)) {
        return candidate.path;
      }
      _log.warning('Rejected invalid TWITCH_FREEDOM_FFMPEG_PATH override.');
    }

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      if (Platform.isLinux) ...<String>[
        '$executableDir/ffmpeg',
        '/usr/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/app/bin/ffmpeg',
      ],
      if (Platform.isMacOS) ...<String>[
        '$executableDir/ffmpeg',
        '/opt/homebrew/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/opt/local/bin/ffmpeg',
      ],
      if (Platform.isWindows) ...<String>[
        '$executableDir\\ffmpeg.exe',
        r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
        r'C:\ffmpeg\bin\ffmpeg.exe',
      ],
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (p.isAbsolute(file.path) &&
          file.existsSync() &&
          _hasExpectedName(file.path)) {
        return file.path;
      }
    }
    return null;
  }

  bool _hasExpectedName(String value) {
    final normalized = value.replaceAll('\\', '/').toLowerCase();
    return normalized.endsWith('/ffmpeg') || normalized.endsWith('/ffmpeg.exe');
  }

  Future<AppResult<File>> extractPcm({
    required Uri input,
    required File output,
    required Duration duration,
  }) async {
    try {
      if (input.scheme != 'https' ||
          input.host.isEmpty ||
          input.userInfo.isNotEmpty) {
        return const AppError<File>(
          AppFailure(
            'unsafe_media_uri',
            'Speech extraction requires a credential-free HTTPS stream URL.',
          ),
        );
      }
      if (!p.isAbsolute(output.path)) {
        return const AppError<File>(
          AppFailure(
            'unsafe_output_path',
            'Speech extraction requires an absolute temporary output path.',
          ),
        );
      }

      final executable = await resolveExecutable();
      if (executable == null) {
        return const AppError<File>(
          AppFailure(
            'ffmpeg_missing',
            'Install system FFmpeg or set TWITCH_FREEDOM_FFMPEG_PATH to an absolute ffmpeg executable.',
          ),
        );
      }

      final safeSeconds = duration.inSeconds.clamp(1, 5).toInt();
      final process = await Process.start(
        executable,
        <String>[
          '-nostdin',
          '-hide_banner',
          '-loglevel',
          'error',
          '-protocol_whitelist',
          'file,http,https,tcp,tls,crypto',
          '-t',
          '$safeSeconds',
          '-i',
          input.toString(),
          '-vn',
          '-ac',
          '1',
          '-ar',
          '16000',
          '-f',
          's16le',
          '-y',
          output.path,
        ],
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      // Drain both pipes concurrently so a noisy process cannot deadlock.
      final stderrFuture = process.stderr
          .transform(systemEncoding.decoder)
          .take(64 * 1024)
          .join();
      final stdoutFuture = process.stdout.drain<void>();
      final exit = await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await stdoutFuture;
      final stderr = await stderrFuture;

      if (exit != 0 || !output.existsSync() || output.lengthSync() == 0) {
        if (output.existsSync()) output.deleteSync();
        throw StateError(
          stderr.trim().isEmpty
              ? 'FFmpeg exited with code $exit.'
              : stderr.trim(),
        );
      }
      return AppSuccess<File>(output);
    } catch (cause) {
      if (output.existsSync()) {
        try {
          output.deleteSync();
        } on FileSystemException {
          // Best-effort cleanup; the caller also destroys the ephemeral file.
        }
      }
      _log.warning('System FFmpeg extraction failed: $cause');
      return AppError<File>(
        AppFailure(
          'system_ffmpeg_failed',
          'Local speech extraction failed.',
          cause: cause,
          retryable: true,
        ),
      );
    }
  }
}
