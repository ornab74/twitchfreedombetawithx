import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';

final class XOAuthTokens {
  const XOAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

final class XOAuthService {
  XOAuthService({required SecureLog log}) : _log = log;

  static const int callbackPort = 27183;
  static final Uri callbackUri = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: callbackPort,
    path: '/x/oauth/callback',
  );

  final SecureLog _log;
  final Random _random = Random.secure();

  Future<AppResult<XOAuthTokens>> authorize(
    String clientId, {
    String clientSecret = '',
  }) async {
    final normalized = clientId.trim();
    if (normalized.length < 10 || normalized.length > 200) {
      return const AppError<XOAuthTokens>(
        AppFailure('x_client_id_invalid', 'Enter a valid X OAuth client ID.'),
      );
    }
    HttpServer? server;
    try {
      final verifier = _randomUrlSafe(64);
      final state = _randomUrlSafe(32);
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        callbackPort,
        shared: false,
      );
      final authorization =
          Uri.https('x.com', '/i/oauth2/authorize', <String, String>{
            'response_type': 'code',
            'client_id': normalized,
            'redirect_uri': callbackUri.toString(),
            'scope': 'tweet.read users.read follows.read offline.access',
            'state': state,
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
          });
      if (!await launchUrl(
        authorization,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Could not open the X authorization page.');
      }
      final request = await server.first.timeout(const Duration(minutes: 3));
      final returnedState = request.uri.queryParameters['state'];
      final code = request.uri.queryParameters['code'];
      final denied = request.uri.queryParameters['error'];
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(
        denied == null && code != null
            ? '<!doctype html><title>Connected</title><p>X connected. Return to Twitch Freedom.</p>'
            : '<!doctype html><title>Not connected</title><p>X authorization was not completed.</p>',
      );
      await request.response.close();
      if (denied != null) {
        return const AppError<XOAuthTokens>(
          AppFailure('x_oauth_denied', 'X authorization was cancelled.'),
        );
      }
      if (returnedState != state || code == null || code.isEmpty) {
        return const AppError<XOAuthTokens>(
          AppFailure(
            'x_oauth_state_invalid',
            'The X authorization callback was rejected.',
          ),
        );
      }
      return _exchange(
        <String, String>{
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': callbackUri.toString(),
          'code_verifier': verifier,
        },
        clientId: normalized,
        clientSecret: clientSecret.trim(),
      );
    } on TimeoutException catch (error) {
      return AppError<XOAuthTokens>(
        AppFailure(
          'x_oauth_timeout',
          'X authorization timed out.',
          cause: error,
        ),
      );
    } catch (error) {
      _log.warning('X OAuth flow failed without credential details: $error');
      return AppError<XOAuthTokens>(
        AppFailure(
          'x_oauth_failed',
          'Could not complete X authorization.',
          cause: error,
        ),
      );
    } finally {
      await server?.close(force: true);
    }
  }

  Future<AppResult<XOAuthTokens>> refresh({
    required String clientId,
    String clientSecret = '',
    required String refreshToken,
  }) => _exchange(
    <String, String>{
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    },
    clientId: clientId.trim(),
    clientSecret: clientSecret.trim(),
  );

  Future<AppResult<XOAuthTokens>> _exchange(
    Map<String, String> body, {
    required String clientId,
    required String clientSecret,
  }) async {
    final client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
    client.badCertificateCallback = (_, __, ___) => false;
    try {
      final request = await client.postUrl(
        Uri.https('api.x.com', '/2/oauth2/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (clientSecret.isEmpty) {
        body['client_id'] = clientId;
      } else {
        final credentials = base64.encode(
          utf8.encode('$clientId:$clientSecret'),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic $credentials',
        );
      }
      request.write(
        body.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );
      final response = await request.close().timeout(AppConfig.networkTimeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(AppConfig.networkTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024)
          throw const FormatException('OAuth response too large.');
      }
      if (response.statusCode != HttpStatus.ok) {
        String detail = '';
        try {
          final rejected = jsonDecode(utf8.decode(bytes));
          if (rejected is Map) {
            detail = (rejected['error_description'] as String?)?.trim() ?? '';
          }
        } catch (_) {
          // The status code still gives a useful, credential-safe failure.
        }
        return AppError<XOAuthTokens>(
          AppFailure(
            'x_oauth_exchange_rejected',
            detail.isEmpty
                ? 'X rejected the OAuth token exchange (HTTP ${response.statusCode}).'
                : 'X rejected authorization: $detail',
          ),
        );
      }
      final payload = jsonDecode(utf8.decode(bytes));
      if (payload is! Map)
        throw const FormatException('Invalid OAuth response.');
      final access = payload['access_token'] as String?;
      final refresh =
          payload['refresh_token'] as String? ?? body['refresh_token'];
      final seconds = (payload['expires_in'] as num?)?.toInt() ?? 7200;
      if (access == null || refresh == null)
        throw const FormatException('OAuth tokens missing.');
      return AppSuccess<XOAuthTokens>(
        XOAuthTokens(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
        ),
      );
    } catch (error) {
      return AppError<XOAuthTokens>(
        AppFailure(
          'x_oauth_exchange_failed',
          'Could not obtain an X user token.',
          cause: error,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  String _randomUrlSafe(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
}
