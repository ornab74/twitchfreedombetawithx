import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/models.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import 'hls_parser.dart';

final class TwitchStreamResolver {
  TwitchStreamResolver({
    required SecureLog log,
    http.Client? client,
    HlsMasterParser parser = const HlsMasterParser(),
  }) : _log = log,
       _client = client ?? http.Client(),
       _parser = parser;

  final SecureLog _log;
  final http.Client _client;
  final HlsMasterParser _parser;
  final Random _random = Random.secure();

  Future<AppResult<ResolvedStream>> resolve(String channel) async {
    final normalized = channel.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(normalized)) {
      return const AppError<ResolvedStream>(
        AppFailure('invalid_channel', 'Enter a valid Twitch channel name.'),
      );
    }
    try {
      final token = await _playbackAccessToken(normalized);
      final masterUri = _usherUri(normalized, token.$1, token.$2);
      _assertTrustedUri(masterUri);
      final manifest = await _boundedGet(
        masterUri,
        maximumBytes: AppConfig.maxManifestBytes,
      );
      final parsed = _parser.parse(manifest, masterUri);
      return parsed.fold(
        success: (List<StreamVariant> variants) => AppSuccess<ResolvedStream>(
          ResolvedStream(
            channel: normalized,
            masterUri: masterUri,
            variants: variants,
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          ),
        ),
        failure: (AppFailure failure) => AppError<ResolvedStream>(failure),
      );
    } catch (error) {
      _log.warning('Twitch resolver failed for $normalized: $error');
      return AppError<ResolvedStream>(
        AppFailure(
          'resolve_failed',
          'Could not resolve a playable Twitch stream.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<(String, String)> _playbackAccessToken(String channel) async {
    final query = <String, Object?>{
      'operationName': 'PlaybackAccessToken',
      'extensions': <String, Object?>{
        'persistedQuery': <String, Object?>{
          'version': 1,
          'sha256Hash': AppConfig.playbackAccessTokenHash,
        },
      },
      'variables': <String, Object?>{
        'isLive': true,
        'login': channel,
        'isVod': false,
        'vodID': '',
        'playerType': 'embed',
        'platform': 'site',
      },
    };
    final response = await _client
        .post(
          AppConfig.twitchGql,
          headers: const <String, String>{
            'Client-ID': AppConfig.publicTwitchWebClientId,
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0 TwitchFreedom/0.1',
          },
          body: jsonEncode(query),
        )
        .timeout(AppConfig.networkTimeout);
    if (response.bodyBytes.length > AppConfig.maxHttpBodyBytes) {
      throw const AppFailure(
        'gql_body_too_large',
        'Twitch playback token response exceeded the safety limit.',
      );
    }
    if (response.statusCode != 200) {
      throw AppFailure(
        'gql_http_error',
        'Twitch playback token request returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<Object?, Object?>)
      throw const FormatException('Unexpected Twitch GraphQL response.');
    final root = Map<String, Object?>.from(decoded);
    final data = Map<String, Object?>.from(
      root['data']! as Map<Object?, Object?>,
    );
    final access = Map<String, Object?>.from(
      data['streamPlaybackAccessToken']! as Map<Object?, Object?>,
    );
    final signature = access['signature'] as String?;
    final value = access['value'] as String?;
    if (signature == null ||
        value == null ||
        signature.isEmpty ||
        value.isEmpty) {
      throw const AppFailure(
        'playback_token_missing',
        'Twitch did not return a playback token. The channel may be offline or restricted.',
      );
    }
    return (signature, value);
  }

  Uri _usherUri(String channel, String signature, String token) {
    return Uri.https(
      'usher.ttvnw.net',
      '/api/channel/hls/$channel.m3u8',
      <String, String>{
        'sig': signature,
        'token': token,
        'allow_source': 'true',
        'allow_audio_only': 'true',
        'playlist_include_framerate': 'true',
        'supported_codecs': 'h264',
        'platform': 'web',
        'player': 'twitchfreedom',
        'p': '${_random.nextInt(999999)}',
      },
    );
  }

  Future<String> _boundedGet(Uri uri, {required int maximumBytes}) async {
    var current = uri;
    for (var redirect = 0; redirect <= AppConfig.maxRedirects; redirect++) {
      _assertTrustedUri(current);
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(const <String, String>{
          'User-Agent': 'Mozilla/5.0 TwitchFreedom/0.1',
          'Accept':
              'application/vnd.apple.mpegurl, application/x-mpegURL, text/plain',
        });
      final response = await _client
          .send(request)
          .timeout(AppConfig.networkTimeout);
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400) {
        if (redirect >= AppConfig.maxRedirects) {
          throw const AppFailure(
            'redirect_limit',
            'The HLS request exceeded its redirect budget.',
          );
        }
        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw const AppFailure(
            'redirect_missing_location',
            'Twitch returned an invalid HLS redirect.',
          );
        }
        final next = current.resolve(location);
        _assertTrustedUri(next);
        current = next;
        continue;
      }
      if (response.statusCode != 200) {
        throw AppFailure(
          'manifest_http_error',
          'Twitch manifest returned HTTP ${response.statusCode}.',
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared > maximumBytes) {
        throw const AppFailure(
          'manifest_too_large',
          'The HLS manifest exceeded the safety limit.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const AppFailure(
            'manifest_too_large',
            'The HLS manifest exceeded the safety limit.',
          );
        }
      }
      return utf8.decode(bytes, allowMalformed: false);
    }
    throw const AppFailure(
      'redirect_limit',
      'The HLS request exceeded its redirect budget.',
    );
  }

  void _assertTrustedUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      throw const AppFailure(
        'untrusted_playback_uri',
        'Playback URLs must be HTTPS URLs without embedded credentials.',
      );
    }
    final host = uri.host.toLowerCase();
    final trusted = AppConfig.trustedPlaybackHostSuffixes.any(
      (String suffix) => host == suffix || host.endsWith('.$suffix'),
    );
    if (!trusted)
      throw AppFailure(
        'untrusted_playback_host',
        'Refused playback redirect to $host.',
      );
  }

  void dispose() => _client.close();
}
