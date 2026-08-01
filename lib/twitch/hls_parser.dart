import '../core/app_config.dart';
import '../core/models.dart';
import '../core/result.dart';

final class HlsMasterParser {
  const HlsMasterParser();

  AppResult<List<StreamVariant>> parse(String source, Uri baseUri) {
    try {
      if (!source.startsWith('#EXTM3U')) {
        return const AppError<List<StreamVariant>>(
          AppFailure(
            'invalid_manifest',
            'The response was not an HLS manifest.',
          ),
        );
      }
      final lines = source.replaceAll('\r\n', '\n').split('\n');
      final variants = <StreamVariant>[];
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final attributes = _parseAttributes(
          line.substring('#EXT-X-STREAM-INF:'.length),
        );
        String? uriLine;
        for (var next = index + 1; next < lines.length; next++) {
          final candidate = lines[next].trim();
          if (candidate.isEmpty) continue;
          if (candidate.startsWith('#')) break;
          uriLine = candidate;
          index = next;
          break;
        }
        if (uriLine == null) continue;
        final uri = baseUri.resolve(uriLine);
        if (!_trustedVariantUri(uri)) continue;
        final resolution = attributes['RESOLUTION'] ?? '';
        final resolutionMatch = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
        final height = resolutionMatch == null
            ? null
            : int.tryParse(resolutionMatch.group(2)!);
        final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '');
        final videoGroup = (attributes['VIDEO'] ?? '').toLowerCase();
        final name = _stripQuotes(
          attributes['NAME'] ?? attributes['VIDEO'] ?? '',
        );
        final audioOnly =
            videoGroup == 'audio_only' || name.toLowerCase().contains('audio');
        final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
        final codecs = _stripQuotes(attributes['CODECS'] ?? '');
        final normalizedName = audioOnly
            ? 'audio_only'
            : name.isNotEmpty
            ? name
            : '${height ?? 0}p${(frameRate ?? 30) >= 50 ? (frameRate ?? 60).round() : ''}';
        variants.add(
          StreamVariant(
            name: normalizedName,
            uri: uri,
            bandwidth: bandwidth,
            height: height,
            frameRate: frameRate,
            audioOnly: audioOnly,
            codecs: codecs,
          ),
        );
      }
      if (variants.isEmpty) {
        return const AppError<List<StreamVariant>>(
          AppFailure(
            'no_variants',
            'The Twitch manifest did not expose playable variants.',
          ),
        );
      }
      variants.sort((StreamVariant left, StreamVariant right) {
        if (left.audioOnly != right.audioOnly) return left.audioOnly ? -1 : 1;
        final height = (left.height ?? 0).compareTo(right.height ?? 0);
        if (height != 0) return height;
        return left.fps.compareTo(right.fps);
      });
      return AppSuccess<List<StreamVariant>>(
        List<StreamVariant>.unmodifiable(variants),
      );
    } catch (error) {
      return AppError<List<StreamVariant>>(
        AppFailure(
          'manifest_parse_failed',
          'The HLS manifest could not be parsed safely.',
          cause: error,
        ),
      );
    }
  }

  Map<String, String> _parseAttributes(String text) {
    final output = <String, String>{};
    final buffer = StringBuffer();
    var quoted = false;
    final parts = <String>[];
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') quoted = !quoted;
      if (char == ',' && !quoted) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    if (buffer.length > 0) parts.add(buffer.toString());
    for (final part in parts) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      output[part.substring(0, separator).trim().toUpperCase()] = _stripQuotes(
        part.substring(separator + 1).trim(),
      );
    }
    return output;
  }

  bool _trustedVariantUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty)
      return false;
    final host = uri.host.toLowerCase();
    return AppConfig.trustedPlaybackHostSuffixes.any(
      (String suffix) => host == suffix || host.endsWith('.$suffix'),
    );
  }

  String _stripQuotes(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

StreamVariant? selectVariant(List<StreamVariant> variants, String requested) {
  if (variants.isEmpty) return null;
  final lower = requested.toLowerCase();
  if (lower == 'audio_only') {
    return variants.where((StreamVariant item) => item.audioOnly).firstOrNull;
  }
  final video = variants
      .where((StreamVariant item) => !item.audioOnly)
      .toList();
  if (video.isEmpty) return null;
  if (lower == 'best' || lower == 'source') return video.last;
  final exact = video
      .where(
        (StreamVariant item) =>
            item.qualityLabel.toLowerCase() == lower ||
            item.name.toLowerCase() == lower,
      )
      .firstOrNull;
  if (exact != null) return exact;
  final match = RegExp(r'^(\d{3,4})p(?:(\d{2,3}))?$').firstMatch(lower);
  if (match == null) return video.last;
  final desiredHeight = int.parse(match.group(1)!);
  final desiredFps = int.tryParse(match.group(2) ?? '') ?? 30;
  video.sort((StreamVariant left, StreamVariant right) {
    final leftDistance =
        ((left.height ?? 0) - desiredHeight).abs() * 1000 +
        (left.fps - desiredFps).abs();
    final rightDistance =
        ((right.height ?? 0) - desiredHeight).abs() * 1000 +
        (right.fps - desiredFps).abs();
    return leftDistance.compareTo(rightDistance);
  });
  return video.first;
}

StreamVariant? selectCpuSafeVariant(
  List<StreamVariant> variants,
  String requested,
) {
  if (requested.toLowerCase() == 'audio_only') {
    return selectVariant(variants, requested);
  }
  final video = variants
      .where((StreamVariant item) => !item.audioOnly)
      .toList(growable: false);
  final safe = video
      .where((StreamVariant item) => (item.height ?? 0) <= 720 && item.fps < 50)
      .toList(growable: false);
  if (safe.isNotEmpty) return selectVariant(safe, requested);

  // Some channels expose only a source/60 FPS rendition. Preserve playback
  // with the least expensive available variant when no 30 FPS option exists.
  final fallback = List<StreamVariant>.of(video)
    ..sort((StreamVariant left, StreamVariant right) {
      final fps = left.fps.compareTo(right.fps);
      if (fps != 0) return fps;
      final height = (left.height ?? 0).compareTo(right.height ?? 0);
      if (height != 0) return height;
      return left.bandwidth.compareTo(right.bandwidth);
    });
  return fallback.firstOrNull;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
